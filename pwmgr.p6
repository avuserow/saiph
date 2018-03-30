#!/usr/bin/env perl6

use v6;
use v6.d.PREVIEW;

use File::HomeDir;
use JSON::Tiny;
use Terminal::Getpass;
use UUID;

class Pwmgr {
	has IO $.path = File::HomeDir.my-home.IO.child('.pwmgr');
	has $!index;

	class Pwmgr::Entry {
		has Str $.uuid;
		has Str $.name is rw;
		has IO $!path;
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

		method all {
			...
		}

		method remove {
			$!path.unlink;
		}
	}
	class Pwmgr::Index {
		constant INDEX_NAME = 'index';
		has IO $.path;
		has Pwmgr $!store;
		has %!map = {};

		# XXX why can't I use TWEAK here?
		submethod BUILD(:$!store) {
			$!path = $!store.path.child(INDEX_NAME);
			if $!path ~~ :e {
				%!map = from-json($!store.encrypted-read($!path));
			}
		}

		method write {
			$!store.encrypted-write($!path, to-json(%!map));
		}

		method all {
			%!map.keys;
		}

		method get($key) {
			%!map{$key};
		}

		method update($key, $value) {
			%!map{$key} = $value;
		}

		method delete($key) {
			%!map{$key}:delete;
		}
	}

	submethod TWEAK {
		$!index = Pwmgr::Index.new(:store(self));
	}

	method create {
		$!path.mkdir; # create if needed
		$!index.write;

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
		$!index.all;
	}

	method new-entry {
		Pwmgr::Entry.new(
			:uuid(UUID.new(:version(4)).Str),
			:store(self),
		);
	}

	method get-entry($key) {
		my $uuid = $!index.get($key);
		if $uuid {
			return Pwmgr::Entry.new(:$uuid, :store(self));
		}
	}

	method save-entry($entry) {
		$entry.write;
		$!index.update($entry.name, $entry.uuid);
		$!index.write;

		self!git-commit("Updated {$entry.uuid}", $entry.uuid, 'index');
	}

	method remove-entry($entry) {
		$entry.remove;
		$!index.delete($entry.name);
		$!index.write;

		!!! "Implement git-rm";
	}

	method !git-commit($message, *@files) {
		my @add = 'git', 'add', '--', |@files;
		run(|@add, :cwd($!path)) or die "Failed to run git: @add[]";

		my @commit = 'git', 'commit', '-m', $message;
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
	$entry.set-key('user', $user);
	$entry.set-key('pass', $pass);
	$pwmgr.save-entry($entry);
}

multi sub MAIN('edit', $key, $user, $pass) {
	my Pwmgr $pwmgr .= new;

	my $entry = $pwmgr.get-entry($key);
	unless $entry {
		die "Could not find entry $key";
	}
	$entry.set-key('user', $user);
	$entry.set-key('pass', $pass);
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
