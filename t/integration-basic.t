#!/usr/bin/env perl6

use v6;
use v6.c;
use Test;

constant APP = 'perl6', 'pwmgr.p6';

subtest {
	run(|APP, <create>);
	run(|APP, <add foo>);
	run(|APP, <set foo bar>, :in).in.spurt('baz', :close);

	my $proc = run(|APP, <show foo bar>, :out);
	my $data = $proc.out.slurp.chomp;
	$proc.sink;
	is $data, 'baz', 'round trip';
}, 'Basic initialization flow';

done-testing;
