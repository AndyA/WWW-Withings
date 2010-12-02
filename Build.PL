use strict;
use warnings;

use Module::Build;

my $build = Module::Build->new(
  module_name       => 'WWW::Withings',
  dist_author       => 'Andy Armstrong <andy@hexten.net>',
  dist_version_from => 'lib/WWW/Withings.pm',
  requires          => {
    'Digest::MD5'    => 0,
    'JSON'           => '2.00',
    'LWP::UserAgent' => '5.815',
    'Test::More'     => 0,
    'accessors::ro'  => 0,
  },
  PL_files       => {},
  add_to_cleanup => ['WWW-Withings-*'],
  sign           => 1,
  license        => 'perl',
  create_readme  => 1,
);

$build->create_build_script;
