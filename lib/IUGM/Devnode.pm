package IUGM::Devnode;

# A Devnode is a filepath to a device file in /dev
# E.g. /dev/ttyUSB0

use Moo;

has devnode => (
    is => 'ro',
    isa => Devnode,
    required => 1,
);

1;

__END__