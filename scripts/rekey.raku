#!/usr/bin/env raku

use Saiph;

my $old = Saiph.new;

my $new = Saiph.new(path => '/tmp/saiph-converted'.IO);
$new.create;

for $old.all -> $key {
	my $entry = $old.get-entry($key);
	my $new-entry = $new.new-entry;
	$new-entry.name = $entry.name;
	$new-entry.map = $entry.map;
	$new.save-entry($new-entry);
}
