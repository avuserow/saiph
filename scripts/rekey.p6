#!/usr/bin/env perl6

use Pwmgr;

my $old = Pwmgr.new;

my $new = Pwmgr.new(path => '/tmp/pwmgr-converted'.IO);
$new.create;

for $old.all -> $key {
	my $entry = $old.get-entry($key);
	my $new-entry = $new.new-entry;
	$new-entry.name = $entry.name;
	$new-entry.map = $entry.map;
	$new.save-entry($new-entry);
}
