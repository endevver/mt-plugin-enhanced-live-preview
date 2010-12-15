#!/usr/bin/env perl

use strict;
use warnings;

use lib qw( t/lib lib extlib );

use MT::Test;
use Test::More tests => 3;

require MT;
ok( MT->component('PreviewShare'), "PreviewShare loaded successfully" );
require_ok('PreviewShare::CMS');
require_ok('PreviewShare::Util');

1;
