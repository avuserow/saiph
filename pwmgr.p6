#!/usr/bin/env perl6

use v6;
use v6.d.PREVIEW;

use File::HomeDir;
use JSON::Tiny;
use UUID;

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
		}
	}

	method !write-index {
		self.encrypted-write(self!index-path, to-json(%!index));
	}

	class Pwmgr::Entry {
		has Str $.uuid;
		has Str $.name is rw;
		has IO $.path;
		has Pwmgr $!store;
		has %!map = {};

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

		method set-key($key, $value) {
			%!map{$key} = $value;
		}

		method get-key($key) {
			%!map{$key};
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
		$path.slurp;
	}

	method encrypted-write(IO $path, Str $data) {
		$path.spurt($data);
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
}

multi sub MAIN('create') {
	my Pwmgr $pwmgr .= new;
	$pwmgr.create;
	say 'Done';
}

multi sub MAIN('list') {
	my Pwmgr $pwmgr .= new;
	.say for $pwmgr.all;
}

multi sub MAIN('add', $key, $user, $pass) {
	my Pwmgr $pwmgr .= new;

	if $pwmgr.get-entry($key) {
		die "$key is already in use";
	}

	my $entry = $pwmgr.new-entry;
	$entry.name = $key;
	$entry.set-key('username', $user);
	$entry.set-key('password', $pass);
	$pwmgr.save-entry($entry);
}

constant TEMPLATE = <username password url>;

sub prompt-prefill($question, $suggestion) {
	use Readline;
	my $rl = Readline.new;
	my $answer;
	my sub line-handler(Str $line) {
		$rl.callback-handler-remove();
		$answer = $line;
	}

	rl_callback_handler_install("$question: ", &line-handler);

	if $suggestion {
		$rl.insert-text($suggestion);
		$rl.redisplay;
	}
	until $answer.defined {
		$rl.callback-read-char();
	}

	return $answer;
}

sub lazy-prompt(&lookup-key) {
	use Readline;
	my $rl = Readline.new;
	my $answer;
	my sub line-handler( Str $line ) {
		rl_callback_handler_remove();
		$answer = $line;
	}

	rl_callback_handler_install("> ", &line-handler);
	#rl_add_funmap_entry(COMPLETE_FN, sub ($a, $b) {});
	my sub key-value-completer(int32 $a, int32 $ord) {
		my $char = $ord.chr;
		my $completion = $char;
		$completion ~= ' ' if $char eq ':'; # format colons nicely

		use NativeCall;
		my $buffer = cglobal('readline', 'rl_line_buffer', Str);

		with &lookup-key($buffer) -> $value {
			$completion ~= $value;
		}
		$rl.insert-text($completion);
	}
	$rl.bind-key(':', &key-value-completer);
	$rl.bind-key('=', &key-value-completer);

	until $answer.defined {
		$rl.callback-read-char();
	}

	return $answer;
}

sub entry-editor($entry) {
	for TEMPLATE -> $field {
		my $result = prompt-prefill($field, $entry.get-key($field));
		$entry.set-key($field, $result);
	}

	# non-template fields
	say "Custom fields. Enter one per line in 'key=value' or 'key: value' formats.";
	say "Existing fields will be pre-filled when you type the separator character.";
	say "Enter a blank line when finished.";
	say "See special commands by entering '.help'.";

	while lazy-prompt(-> $key {$entry.get-key($key)}) -> $line {
		last unless $line;

	}
}

multi sub MAIN('edit', $key) {
	my Pwmgr $pwmgr .= new;

	my $entry = $pwmgr.get-entry($key);
	unless $entry {
		die "Could not find entry $key";
	}
	entry-editor($entry);
	$pwmgr.save-entry($entry);
}

multi sub MAIN('delete', $key) {
	my Pwmgr $pwmgr .= new;

	my $entry = $pwmgr.get-entry($key);
	unless $entry {
		die "Could not find entry $key";
	}
	$pwmgr.remove-entry($entry);
}
