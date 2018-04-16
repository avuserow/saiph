use v6.d.PREVIEW;

use File::HomeDir;
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
	has IO $.path = File::HomeDir.my-home.IO.child('.pwmgr');
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

sub lazy-prompt(&lookup-key, :$hard-key, :@all-keys) is export {
	use Readline;
	my $rl = Readline.new;
	my $answer;
	my $done = False;
	my sub line-handler(Str $line) {
		rl_callback_handler_remove();
		$answer = $line;
		$done = True;
	}

	my $question = $hard-key ?? "$hard-key: " !! '> ';
	rl_callback_handler_install($question, &line-handler);

	my sub key-value-completer(int32 $a, int32 $ord) {
		my $char = $ord.chr;
		my $completion = $char;
		$completion ~= ' ' if $char eq ':'; # format colons nicely

		use NativeCall;
		my $buffer = cglobal('readline', 'rl_line_buffer', Str);

		$completion ~= &lookup-key($buffer) // '';
		$rl.insert-text($completion);
	}

	# Tab completion reimplementation, since we can't hook into the system one
	my sub tab-completer(int32 $a, int32 $b) {
		use NativeCall;
		my $buffer = cglobal('readline', 'rl_line_buffer', Str);

		# Make a copy that unifies hard-key and regular mode
		my $tempbuffer = $hard-key ?? "$hard-key: $buffer" !! $buffer;
		# XXX tighten up this buffer parsing logic to be unified with other
		# uses, and to make the whitespace handling consistent/easier
		if $tempbuffer ~~ /(.+)\s*<[:=]>\s?$/ {
			my $key = $0.Str;
			my $completion ~= &lookup-key($key) // '';
			$rl.insert-text($completion);
		} elsif $tempbuffer !~~ /<[:=]>/ {
			my @matches = @all-keys.grep: *.starts-with($buffer);
			if @matches == 0 {
				# nothing matched, do nothing
			} elsif @matches == 1 {
				$rl.insert-text(@matches[0].substr($buffer.chars));
			} elsif @matches < 25 {
				say "";
				# XXX: split this "column-wise" as opposed to the current
				# row-wise to be more like bash's completion
				for @matches.rotor(2, :partial) {
					say sprintf("%-40s%-40s", |$_);
				}
				$rl.forced-update-display;
			} else {
				say "";
				say "Found {+@matches} fields. Use .keys to list them or be more specific.";
				$rl.forced-update-display;
			}
		}

		# we crash unless returning false here
		return False;
	}

	if $hard-key {
		with &lookup-key($hard-key) -> $value {
			$rl.insert-text($value);
			$rl.redisplay;
		}
	} else {
		# XXX evaluate removing this
		# $rl.bind-key(':', &key-value-completer);
		# $rl.bind-key('=', &key-value-completer);
	}
	$rl.bind-key('	', &tab-completer);

	$rl.callback-read-char() until $done;
	return $answer;
}

constant ENTRY_EDITOR_HELP = q:to/END/;

Enter custom fields. Enter one per line in 'key=value' or 'key: value' formats.
Existing fields will be pre-filled when you type the separator character.
See special commands by entering '.help'.
Enter a blank line when finished.
END

sub entry-editor($entry) is export {
	for TEMPLATE -> $field {
		my $result = lazy-prompt(-> $key {$entry.map{$key}}, :hard-key($field));
		$entry.map{$field} = $result;
	}

	# non-template fields
	say ENTRY_EDITOR_HELP;

	while lazy-prompt(-> $key {$entry.map{$key}}, :all-keys($entry.map.keys.sort)) -> $line is copy {
		# Remove extra whitespace.
		$line .= trim;

		# Empty line means we're done.
		last unless $line;

		# Is it a command?
		if $line.starts-with('.') {
			my @words = $line.words;
			given @words[0] {
				when '.help' {
					say ENTRY_EDITOR_HELP;
				}
				when '.keys' {
					say $entry.map.keys;
				}
				default {
					say "Unknown command '@words[0]'. Use '.help' for help.";
				}
			}
			next;
		}

		# Is it a valid key/value pair?
		with $line.match(/^(<-[:=]>+) \s* <[:=]> \s* (.*)$/) { # ' highlight fix
			my $k = $0.Str;
			my $v = $1.Str;
			$entry.map{$k} = $v;
			next;

			# Invalid key syntax is an exception, just print it here
			CATCH {default {.say; next;}}
		}

		say "Unknown syntax. Use '.help' for help.";
	}
}

