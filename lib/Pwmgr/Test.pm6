use v6;

constant APP = 'pwmgr.p6';

sub run-cli(|args) is export {
	run(|APP, |args);
}

sub run-cli-output(|args) is export {
	my $proc = run(|APP, |args, :out);
	my $data = $proc.out.slurp.chomp;
	$proc.sink;
	$data;
}
