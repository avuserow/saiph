#!/usr/bin/env perl6

use v6;
use v6.c;
use Test;
use Pwmgr::Test;

subtest {
	run-cli(<create>);
	run-cli(<add foo>);
	run-cli(<set foo bar>, :in).in.spurt('baz', :close);

	my $proc = run-cli(<show foo bar>, :out);
	my $data = $proc.out.slurp.chomp;
	$proc.sink;
	is $data, 'baz', 'round trip';
}, 'Basic initialization flow';

done-testing;
