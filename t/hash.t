#!perl

package FakeWithings;

use strict;
use warnings;

use base qw( WWW::Withings );

sub get_otp { '4a8947d9-25e849fd' }

package main;

use strict;
use warnings;
use Test::More tests => 1;

use WWW::Withings;

my $wi = FakeWithings->new( userid => '', publickey => '' );
is $wi->hash( 'demo@withings.com', 'bozo' ),
 '99eb3bc8555ca782fa4a0fda53bc8a1a', 'hash';

# vim:ts=2:sw=2:et:ft=perl

