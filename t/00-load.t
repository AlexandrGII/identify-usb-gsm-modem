#!perl -T
use 5.006;
use strict;
use warnings;
use Test::More;

plan tests => 6;

BEGIN {
    use_ok( 'IUGM' ) || print "Bail out!\n";
    use_ok( 'IUGM::Cache' ) || print "Bail out!\n";
    use_ok( 'IUGM::Config' ) || print "Bail out!\n";
    use_ok( 'IUGM::Sysfs' ) || print "Bail out!\n";
    use_ok( 'IUGM::Error' ) || print "Bail out!\n";
    use_ok( 'IUGM::Modem' ) || print "Bail out!\n";
}

diag( "Testing IUGM $IUGM::VERSION, Perl $], $^X" );
