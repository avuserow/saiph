#!/usr/bin/env perl6

use v6;
use v6.c;
use Test;
use Pwmgr::Test;

subtest {
	run-cli(<create>);
	run-cli(<add foo>);
	run-cli(<set foo bar>, :in).in.spurt('baz', :close);

	is run-cli-output(<show foo bar>), 'baz', 'round trip';
}, 'Basic roundtrip flow';

done-testing;
