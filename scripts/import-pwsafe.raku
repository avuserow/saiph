#!/usr/bin/env raku

use v6;
use v6.d.PREVIEW;

use HTML::Entity;

sub MAIN() {
	for lines() -> $line {
		next if $line eq '# passwordsafe version 2.0 database';
		next if $line eq <uuid group name login passwd notes>.join("\t");
		my ($uuid, $group, $name, $login, $passwd, $notes) = $line.split(/\t/);

		for ($group, $name, $login, $passwd, $notes) {
			s/^ \"(.*)\" $/$0/ if .starts-with('"') and .ends-with('"');
			$_ .= &decode-entities;
		}

		my $key = $name;
		$key = "$group.$name" if $group;

		say $key;
		run('saiph.p6', 'add', $key);
		run('saiph.p6', 'set', $key, 'username', :in).in.spurt($login, :close);
		run('saiph.p6', 'set', $key, 'password', :in).in.spurt($passwd, :close);
		run('saiph.p6', 'set', $key, 'notes', :in).in.spurt($notes, :close);
	}
}
