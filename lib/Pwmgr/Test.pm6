use v6;

constant APP = 'pwmgr.p6';

sub run-cli(|args) is export {
	run(|APP, |args);
}
