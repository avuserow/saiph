use v6;

use Test;
use File::Which;

use-ok 'Saiph';

ok which('git'), 'git in PATH';
ok which('gpg2'), 'gpg2 in PATH';
ok which('xclip'), 'xclip in PATH';

done-testing;
