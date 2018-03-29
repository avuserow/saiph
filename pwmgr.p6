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
				%!map = from-json($!store.encrypted-read($!path));
			}
		}

		method write {
			$!store.encrypted-write($!path, to-json(%!map));
		}

		method set-key($key, $value) {
			%!map{$key} = $value;
		}
	}
	class Pwmgr::Index {
		constant INDEX_NAME = 'index';
		has IO $!path;
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

		method update($key, $value) {
			%!map{$key} = $value;
		}
	}

	submethod TWEAK {
		$!index = Pwmgr::Index.new(:store(self));
	}

	method create {
		$!path.mkdir; # create if needed
		$!index.write;
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

	method save-entry($entry) {
		$entry.write;
		$!index.update($entry.uuid, $entry.name);
		$!index.write;
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
	my $entry = $pwmgr.new-entry;
	$entry.name = $key;
	$entry.set-key('user', $user);
	$entry.set-key('pass', $pass);
	$pwmgr.save-entry($entry);
}
