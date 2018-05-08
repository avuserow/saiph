use v6.d.PREVIEW;

use JSON::Tiny;
use UUID;

class X::Pwmgr::Error is Exception {
	has $.message;
	method new($message) {self.bless(:$message);}
	method gist {$!message}
}

constant KEY_PATTERN = rx/<[a..zA..Z0..9]><[a..zA..Z0..9._/]>*/;
class Pwmgr {
	constant INDEX = 'index';
	has IO $.path = $*HOME.child('.pwmgr');
	has %!index;

	submethod TWEAK {
		self!read-index;
	}

	method !index-path {
		$!path.child(INDEX);
	}

	method !read-index {
		if self!index-path ~~ :e {
			%!index = from-json(self.encrypted-read(self!index-path));
			CATCH {
				default {
					say "Reading index failed. Try rebuilding the index.";
					.throw;
				}
			}
		}
	}

	method !write-index {
		self.encrypted-write(self!index-path, to-json(%!index));
	}

	# XXX: consider whether we should flatten this into a single hash,
	# and not differentiate between user data and our data aside from a simple
	# whitelist and beginning with a . or similar
	class Pwmgr::Entry {
		has Str $.uuid;
		has Str $.name is rw;
		has IO $.path;
		has Pwmgr $!store;

		subset EntryKey of Str where * ~~ /^$(KEY_PATTERN)$/;
		has %.map{EntryKey};

		submethod BUILD(:$!store, :$!uuid) {
			$!path = $!store.path.child($!uuid);
			if $!path ~~ :e {
				my %data = from-json($!store.encrypted-read($!path));
				$!name = %data<name>;
				%!map = %data<map>;
			}
		}

		method write {
			my $serialized = to-json({
				:$!name,
				:%!map,
			});
			$!store.encrypted-write($!path, $serialized);
		}

		method remove {
			$!path.unlink;
		}
	}

	method create {
		$!path.mkdir; # create if needed
		self!write-index;

		my @git = 'git', 'init';
		run(|@git, :cwd($!path)) or die "Failed to run git: @git[]";

		self!git-commit('Initial commit.', 'index');
	}

	method encrypted-read(IO $path) {
		my @gpg = 'gpg2', '--quiet', '--decrypt', $path;
		my $proc = run(|@gpg, :out) // die "Failed to run gpg2: @gpg[]";
		my $data = $proc.out.slurp(:close);
		$proc.sink;
		return $data;
	}

	method encrypted-write(IO $path, Str $data) {
		my $fh = open $path, :w;
		my @gpg = 'gpg2', '--quiet', '--encrypt', '--default-recipient-self';
		my $proc = run(|@gpg, :in, :out($fh)) // die "Failed to run gpg2: @gpg[]";
		$proc.in.spurt($data, :close);
		$proc.sink;
	}

	method all {
		%!index.keys;
	}

	method new-entry {
		Pwmgr::Entry.new(
			:uuid(UUID.new(:version(4)).Str),
			:store(self),
		);
	}

	method get-entry($key) {
		with %!index{$key} -> $uuid {
			return Pwmgr::Entry.new(:$uuid, :store(self));
		}
	}

	#| Find entries 
	method find-entry($name) {
		# Check for an exact match
		.return with self.get-entry($name);

		# Check for a prefix match
		my @matches = %!index.keys.grep(*.starts-with($name)).map({self.get-entry($_)});
		return @matches if @matches;

		# Check for match at a word boundary
		return %!index.keys.grep(/<|w>$name/).map({self.get-entry($_)});
	}

	#| Find an entry and return an error unless exactly one is found.
	method smartfind($name) {
		my @entries = self.find-entry($name);
		if @entries == 1 {
			return @entries[0];
		} elsif @entries == 0 {
			die X::Pwmgr::Error("No matching entry found.");
		} else {
			die X::Pwmgr::Error.new("More than one matching entry: {@entries>>.name.join(', ')}");
		}
	}

	method save-entry($entry) {
		$entry.write;
		%!index{$entry.name} = $entry.uuid;
		self!write-index;

		self!git-commit("Updated {$entry.uuid}", $entry.path, INDEX);
	}

	method remove-entry($entry) {
		$entry.remove;
		%!index{$entry.name}:delete;
		self!write-index;

		my @rm = 'git', 'rm', '--', $entry.path;
		run(|@rm, :cwd($!path)) or die "Failed to run git: @rm[]";

		self!git-commit("Removed {$entry.uuid}", INDEX);
	}

	method !git-commit($message, *@files) {
		my @add = 'git', 'add', '--', |@files;
		run(|@add, :cwd($!path)) or die "Failed to run git: @add[]";

		my @commit = 'git', 'commit', '-m', $message, '--allow-empty';
		run(|@commit, :cwd($!path)) or die "Failed to run git: @commit[]";
	}

	method to-clipboard($value) {
		my @xclip = 'xclip', '-loops', '1', '-quiet';
		my $proc = run(|@xclip, :in) // die "Failed to run xclip: @xclip[]";
		$proc.in.spurt($value, :close);
	}
}

constant TEMPLATE = <username password url>;

constant ENTRY_EDITOR_HELP = q:to/END/;

Enter custom fields. Enter one per line in 'key=value' or 'key: value' formats.
Existing fields will be pre-filled when you type the separator character.
See special commands by entering '.help'.
Enter a blank line when finished.
END


# Readline prompter. Handles the following cases:
# 1) Command/Field entry. Tab complete for fields and verbs.
# 2) Value editor (regular). Prefill previous value. Tab completes existing.
# 3) Value editor (password). Echo off, no prefill, special instructions.
# Other things:
# - keybinding for abort without change
enum PromptMode <CommandEntry ValueEditor PasswordEditor>;
sub adv-prompt(PromptMode $mode, $prompt, :@completions) {
	use Readline;
	my $rl = Readline.new;
	my $answer;
	my $done = False;
	my sub line-handler(Str $line) {
		rl_callback_handler_remove();
		$answer = $line;
		$done = True;
	}

	# Tab completion reimplementation, since we can't hook into the system one
	my sub tab-completer(int32 $a, int32 $b) {
		use NativeCall;
		my $buffer = cglobal('readline', 'rl_line_buffer', Str);
		if $mode ~~ CommandEntry {
			my @matches = @completions.sort.grep: *.starts-with($buffer);
			if @matches == 1 {
				$rl.insert-text(@matches[0].substr($buffer.chars));
			} elsif @matches > 1 { # maybe add a cut-off at some point
				# Display matches in two columns, going down (like how bash does it)
				say "";
				my $rows = ceiling(@matches / 2);
				say |$_ for roundrobin @matches>>.fmt('%-40.32s').rotor($rows => 0, :partial);
				$rl.forced-update-display;
			}
		} elsif $mode ~~ ValueEditor {
			$rl.insert-text(@completions[0] // '') if $buffer eq '';
		} elsif $mode ~~ PasswordEditor {
			say "\nNo tab completion for passwords.";
			$rl.forced-update-display;
		}

		return False; # we crash unless returning false here
	}

	rl_callback_handler_install($prompt, &line-handler);
	$rl.insert-text(@completions[0] // '') if $mode ~~ ValueEditor;
	$rl.redisplay;
	$rl.bind-key("\t", &tab-completer);

	$rl.callback-read-char() until $done;
	return $answer;
}

my %REPL = (
	'.keys' =>
		#| .keys: List the keys defined for this entry.
		-> :$entry {say $entry.map.keys},
	'.show' =>
		#| .show <key>: show the given key for this entry
		-> $key, :$entry {say $entry.map{$key} // ''},
	'.editor' =>
		#| .editor <key>: edit the given key in vim
		-> $key, :$entry {
			note 'run vim here';
		},
	'.help' =>
		#| .help: See help for the editor and a list of commands
		-> *%_ {
			say ENTRY_EDITOR_HELP;
			say %REPL{$_}.WHY for %REPL.keys.sort;
		},
);

sub simple-entry-editor($entry) is export {
	say "Editing {$entry.name}";
#	for TEMPLATE -> $field {
#		my $result = prompt "$field: ";
#		$entry.map{$field} = $result;
#	}

	say ENTRY_EDITOR_HELP;
	loop { # REPL loop
		my $line = adv-prompt(CommandEntry, '> ', :completions(flat(%REPL.keys, $entry.map.keys)));
		$line .= trim;
		last unless $line; # empty line terminates

		my ($verb, @words) = $line.words;
		with %REPL{$verb} -> &cmd {
			&cmd(|@words, :$entry);
			CATCH {
				default {
					say $_, "\n", "Usage: ", %REPL{$verb}.WHY;
				}
			}
		} elsif $line ~~ /^$(KEY_PATTERN)$/ {
			my $old-value = $entry.map{$line} // '';
			my $mode = $line eq 'password' ?? PasswordEditor !! ValueEditor;
			my $value = adv-prompt($mode, "$line: ", :completions([$old-value]));
			$entry.map{$line} = $value;
		} else {
			say "Unknown command.";
			say ENTRY_EDITOR_HELP;
		}
	}
}
