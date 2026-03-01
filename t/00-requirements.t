use v6;

use Test;
use File::Which;

use-ok 'Saiph';

ok which('git'), 'git in PATH';

done-testing;
