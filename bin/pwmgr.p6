#!/usr/bin/env perl6

use v6;
use v6.d.PREVIEW;

use Pwmgr;

#| Initialize the database.
multi sub MAIN('create') {
	my Pwmgr $pwmgr .= new;
	$pwmgr.create;
	say 'Done';
}

#| List all entries in the database.
multi sub MAIN('list') {
	my Pwmgr $pwmgr .= new;
	.say for $pwmgr.all.sort;
}

#| Add an entry to the database.
multi sub MAIN('add', $key, $user?, $pass?) {
	my Pwmgr $pwmgr .= new;

	if $pwmgr.get-entry($key) {
		die "$key is already in use";
	}

	my $entry = $pwmgr.new-entry;
	$entry.name = $key;
	$entry.map<username> = $user;
	$entry.map<password> = $pass;
	$pwmgr.save-entry($entry);
}

#| Edit the provided entry via an interactive editor.
multi sub MAIN('edit', $key) {
	my Pwmgr $pwmgr .= new;

	my $entry = $pwmgr.get-entry($key);
	die "Could not find entry $key" unless $entry;
	simple-entry-editor($entry);
	$pwmgr.save-entry($entry);
}

#| Remove an entry from the database.
multi sub MAIN('delete', $key) {
	my Pwmgr $pwmgr .= new;

	my $entry = $pwmgr.get-entry($key);
	die "Could not find entry $key" unless $entry;
	$pwmgr.remove-entry($entry);
}

#| Show all keys for the specified entry.
multi sub MAIN('show', $entry) {
	my Pwmgr $pwmgr .= new;
	my $e = $pwmgr.get-entry($entry) // die "Could not find entry $entry";
	.say for $e.map.keys;
}

#| Show the specified entry's value for the specified key.
multi sub MAIN('show', $key, $field) {
	my Pwmgr $pwmgr .= new;
	my $entry = $pwmgr.get-entry($key) // die "Could not find entry $key";
	say $entry.map{$field} // die "Field $field not found in entry $key";
}

#| Set the provided entry's field from STDIN (primarily for automation)
multi sub MAIN('set', $key, $field) {
	my Pwmgr $pwmgr .= new;
	my $entry = $pwmgr.get-entry($key);
	my $value = $*IN.lines()[0];
	$entry.map{$field} = $value;
	$pwmgr.save-entry($entry);
}

#| With the specified entry, copy its field onto the clipboard.
multi sub MAIN('clip', $entry, $field) {
	my Pwmgr $pwmgr .= new;
	my $e = $pwmgr.get-entry($entry) // die "Could not find entry $entry";
	my $value = $e.map{$field} // die "Field $field not found in entry $entry";
	$pwmgr.to-clipboard($value);
}

#| Find an entry by name and use it.
multi sub MAIN('auto', $name) {
	my Pwmgr $pwmgr .= new;
	my $entry = $pwmgr.smartfind($name);
}

#| Process global CLI arguments that are specified before the subcommand
#| These values are exported as dynamic variables
#sub process-global-args(@args) {
#	my $found-verb = False;
#	my %values;
#	loop (my $i = 0; $i < @args; $i++) {
#		if @args[$i] ~~ /^'--' (<[a..zA..Z-]>+)$/ {
#			%values{$0.Str} = @args[$i+1];
#			$i++;
#		} elsif @args[$i] ~~ /^'--' (<[a..zA..Z-]>+) '=' (.+)$/ {
#			%values{$0.Str} = $1.Str;
#		} else {
#			$found-verb = True;
#			last;
#		}
#	}
#
#	# Only modify if we found a verb
#	if $found-verb {
#		@args.splice(0, $i);
#		$*database = %values<d> // %values<database>;
#	}
#}
#
#process-global-args(@*ARGS);
