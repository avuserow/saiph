#!/usr/bin/env perl6

use v6;
use v6.d.PREVIEW;

use Pwmgr;
my Pwmgr $pwmgr .= new;

#| Initialize the database.
multi sub MAIN('create') {
	$pwmgr.create;
	say 'Done';
}

multi sub MAIN('add', $key) {
	my $entry = $pwmgr.get-entry($key);
	die "Entry $key already exists" if $entry;
	say "New entry $key";
	$entry = $pwmgr.new-entry;
	$entry.name = $key;
	$pwmgr.save-entry($entry);
}

#| List all entries in the database.
multi sub MAIN('list') {
	.say for $pwmgr.all.sort;
}

#| Add or edit the provided entry via an interactive editor.
multi sub MAIN('edit', $key) {
	my $entry = $pwmgr.get-entry($key);
	if $entry {
		say "Editing $key";
	} else {
		say "New entry $key";
		$entry = $pwmgr.new-entry;
		$entry.name = $key;
	}
	simple-entry-editor($entry);
	$pwmgr.save-entry($entry);
}

#| Remove an entry from the database.
multi sub MAIN('delete', $key) {
	my $entry = $pwmgr.get-entry($key);
	die "Could not find entry $key" unless $entry;
	$pwmgr.remove-entry($entry);
}

#| Show all keys for the specified entry.
multi sub MAIN('show', $entry) {
	my $e = $pwmgr.get-entry($entry) // die "Could not find entry $entry";
	.say for $e.map.keys;
}

#| Show the specified entry's value for the specified field.
multi sub MAIN('show', $key, $field) {
	my $entry = $pwmgr.get-entry($key) // die "Could not find entry $key";
	say $entry.map{$field} // die "Field $field not found in entry $key";
}

#| Set the provided entry's field from STDIN (primarily for automation)
multi sub MAIN('set', $key, $field) {
	my $entry = $pwmgr.get-entry($key);
	my $value = $*IN.lines()[0];
	$entry.map{$field} = $value;
	$pwmgr.save-entry($entry);
}

#| With the specified entry, copy its field onto the clipboard.
multi sub MAIN('clip', $entry, $field) {
	my $e = $pwmgr.get-entry($entry) // die "Could not find entry $entry";
	my $value = $e.map{$field} // die "Field $field not found in entry $entry";
	$pwmgr.to-clipboard($value);
}

#| Find an entry by name and use it.
multi sub MAIN('auto', $name) {
	my $entry = $pwmgr.smartfind($name);
}
