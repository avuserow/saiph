use v6.d;

use JSON::Tiny;
use UUID;

class X::Pwmgr::Error is Exception {
	has $.message;
	method new($message) {self.bless(:$message);}
	method gist {$!message}
}

class X::Pwmgr::EditorAbort is X::Pwmgr::Error {}

constant KEY_PATTERN = rx/<[a..zA..Z0..9]><[a..zA..Z0..9._/]>*/;
class Pwmgr {
	use Pwmgr::Crypt;
	has $.crypt-backend is rw;
	has IO $.path = IO;
	has %!index;

	submethod TWEAK {
		$!path //= $*HOME.child('.pwmgr');
		self!determine-crypt-backend unless $!crypt-backend;
		self!read-index;
	}

	method !determine-crypt-backend {
		constant CRYPT_BACKENDS = <SecretBox GPG>;
		for CRYPT_BACKENDS -> $short-backend {
			my $backend = ::("Pwmgr::Crypt::$short-backend");
			if $.path.child($backend.index-path) ~~ :f {
				$.crypt-backend = $backend.new;
				last;
			}
		}

		# no database found, use the default
		$.crypt-backend //= ::("Pwmgr::Crypt::" ~ CRYPT_BACKENDS[0]).new;
	}

	method !index-path {
		$!path.child($.crypt-backend.index-path);
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

		self!git-commit('Initial commit.', self!index-path);
	}

	method encrypted-read(IO $path) {
		$.crypt-backend.encrypted-read($path);
	}

	method encrypted-write(IO $path, Str $data) {
		$.crypt-backend.encrypted-write($path, $data);
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

	#| Get an entry by key (exact match)
	method get-entry($key) {
		with %!index{$key} -> $uuid {
			return Pwmgr::Entry.new(:$uuid, :store(self));
		}
	}

	#| Find one or more entries using a few different matching techniques
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
			die X::Pwmgr::Error.new("No matching entry found.");
		} else {
			die X::Pwmgr::Error.new("More than one matching entry: {@entries>>.name.join(', ')}");
		}
	}

	method save-entry($entry) {
		$entry.write;
		%!index{$entry.name} = $entry.uuid;
		self!write-index;

		self!git-commit("Updated {$entry.uuid}", $entry.path, self!index-path);
	}

	method remove-entry($entry) {
		$entry.remove;
		%!index{$entry.name}:delete;
		self!write-index;

		my @rm = 'git', 'rm', '--', $entry.path;
		run(|@rm, :cwd($!path)) or die "Failed to run git: @rm[]";

		self!git-commit("Removed {$entry.uuid}", self!index-path);
	}

	method !git-commit($message, *@files) {
		my @add = 'git', 'add', '--', |@files;
		run(|@add, :cwd($!path)) or die "Failed to run git: @add[]";

		my @commit = 'git', 'commit', '-m', $message, '--allow-empty';
		run(|@commit, :cwd($!path)) or die "Failed to run git: @commit[]";
	}

	method to-clipboard($value) {
		# use -wait 100 to handle apps reading from the buffer multiple times
		# similar to -sensitive but with a longer timeout
		my @xclip = 'xclip', '-wait', 100, '-quiet';
		my $proc = run(|@xclip, :in) // die "Failed to run xclip: @xclip[]";
		$proc.in.spurt($value, :close);
	}
}

constant TEMPLATE = <username password>;

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
multi adv-prompt(PromptMode $mode, $prompt, :@completions) {
	# Readline does not provide an appropriate mode for secrets
	if $mode ~~ PasswordEditor {
		use Terminal::Getpass;
		return getpass($prompt);
		CATCH {
			# Getpass throws an untyped exception with ctrl+c
			default {
				say ""; # clear the line
				return Nil;
			}
		}
	}

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
			# only a single possible completion for values, so add it if the buffer is empty
			$rl.insert-text(@completions[0] // '') if $buffer eq '';
		}

		return False; # we crash unless returning false here
	}

	rl_callback_handler_install($prompt, &line-handler);
	$rl.insert-text(@completions[0] // '') if $mode ~~ ValueEditor;
	$rl.redisplay;
	$rl.bind-key("\t", &tab-completer);
	# XXX catch ctrl+c here somehow

	$rl.callback-read-char() until $done;
	return $answer;
}

my %REPL = (
	'.abort' =>
		#| .abort: quit without saving changes
		-> *%_ {die X::Pwmgr::EditorAbort('exiting')},
	'.keys' =>
		#| .keys: list the keys defined for this entry.
		-> :$entry {say $entry.map.keys},
	'.show' =>
		#| .show <key>: show the given key for this entry
		-> $key, :$entry {say $entry.map{$key} // ''},
	'.move' =>
		#| .move <oldkey> <newkey>: move the given key
		-> $oldkey, $newkey, :$entry {
			if $entry.map{$newkey}:exists {
				say "Cannot move $oldkey -> $newkey - destination already exists";
			} else {
				$entry.map{$newkey} = $entry.map{$oldkey}:delete;
			}
		},
	'.delete' =>
		#| .delete <key>: delete the specified key
		-> $key, :$entry {
			$entry.map{$key}:delete;
		},
	'.help' =>
		#| .help: See help for the editor and a list of commands
		-> *%_ {
			say ENTRY_EDITOR_HELP;
			say %REPL{$_}.WHY for %REPL.keys.sort;
		},
);

sub simple-entry-editor($entry) is export {
#	for TEMPLATE -> $field {
#		my $result = prompt "$field: ";
#		$entry.map{$field} = $result;
#	}

	say ENTRY_EDITOR_HELP;
	loop { # REPL loop
		my $line = adv-prompt(CommandEntry, '> ', :completions(flat(%REPL.keys, $entry.map.keys)));
		$line .= trim;
		last unless $line; # empty line terminates and saves

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
			if $value {
				$entry.map{$line} = $value;
			} else {
				say "Keeping $line as-is. Use `.delete $line` to remove it.";
			}
		} else {
			say "Unknown command.";
			say ENTRY_EDITOR_HELP;
		}
	}
}
