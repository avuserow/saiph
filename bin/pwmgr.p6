#!/usr/bin/env perl6

use v6.d;

use Pwmgr;
my Pwmgr $pwmgr .= new;

#| Initialize the database.
multi sub MAIN('create') {
	$pwmgr.create;
	say 'Done';
}

multi sub MAIN('add', $key) {
	die "Entry $key already exists" if $pwmgr.get-entry($key);
	say "New entry $key";
	my $entry = $pwmgr.new-entry;
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
	CATCH {
		when X::Pwmgr::EditorAbort {
			say 'Exiting without changes';
		}
	}
}

#| Remove an entry from the database.
multi sub MAIN('delete', $key) {
	my $entry = $pwmgr.get-entry($key);
	die "Could not find entry $key" unless $entry;
	$pwmgr.remove-entry($entry);
}

#| Show all keys for the specified entry.
multi sub MAIN('show', $entry, Bool :$exact-match=False) {
	my $e;
	if $exact-match {
		$e = $pwmgr.get-entry($entry) // die "Could not find entry $entry";
	} else {
		$e = $pwmgr.smartfind($entry) // die "Could not find entry $entry";
	}
	.say for $e.map.keys;
}

#| Show the specified entry's value for the specified field.
multi sub MAIN('show', $entry, $field, Bool :$exact-match=False) {
	my $e;
	if $exact-match {
		$e = $pwmgr.get-entry($entry) // die "Could not find entry $entry";
	} else {
		$e = $pwmgr.smartfind($entry) // die "Could not find entry $entry";
	}
	say $e.map{$field} // die "Field $field not found in entry $entry";
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

	for TEMPLATE -> $field {
		say "[$entry.name()] Copied $field to clipboard";
		$pwmgr.to-clipboard($entry.map{$field} // '');
	}
}
