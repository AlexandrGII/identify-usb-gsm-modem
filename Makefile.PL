use 5.006;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'IUGM',
    AUTHOR           => q{Patrick Cronin <patrick@cronin-tech.com>},
    VERSION_FROM     => 'lib/IUGM.pm',
    ABSTRACT_FROM    => 'lib/IUGM.pm',
    LICENSE          => 'artistic_2',
    PL_FILES         => {},
    MIN_PERL_VERSION => 5.006,
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 0,
    },
    BUILD_REQUIRES => {
        'Test::More' => 0,
    },
    PREREQ_PM => {
        'DBD::SQLite' => 1,
        'DBI' => 1,
        'Device::Modem' => 1,
        'IO::Interactive' => 1,
        'Modern::Perl' => 1,
        'MooX::Options' => 1,
        'MooX::Singleton' => 1,
        'MooX::Types::MooseLike::Base' => 1,
        'Path::Tiny' => 1,
        'Throwable::Error' => 1,
        'Types::Path::Tiny' => 1,
        'Readonly' => 1,
        'Sub::Quote' => 1,
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES => 'IUGM-*' },
);
