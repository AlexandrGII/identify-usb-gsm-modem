package IUGM::Sysfs::Path;

# A Devpath is a filepath to a device record within the Sysfs tree
# E.g. /sys/devices/platform/soc/3f98000.usb/usb1/1-1/1-1.4/1-1.4:1.0/ttyUSB0/tty/ttyUSB0

use Moo;
use IUGM::Types;
use IUGM::Config;
use Path::Tiny;
use List::Util qw( first );
use Readonly;

our $VERSION = '0.01';

Readonly my $VENDOR_ID_ATTRIBUTE => 'idVendor';
Readonly my $PRODUCT_ID_ATTRIBUTE => 'idProduct';
Readonly my $INTERFACE_NUMBER_ATTRIBUTE => 'bInterfaceNumber';
Readonly my $CONFIGURATION_VALUE_ATTRIBUTE => 'bConfigurationValue';

has path => (
    is => 'ro',
    isa => SysfsPath,
    required => 1,
);

has _device_root => (
    is => 'ro',
    isa => SysfsPath,
    builder => 1,
    lazy => 1,
);

# The device root contains the idVendor and idProduct attributes
sub _build__device_root {
    my $self = shift;
    
    return $self->_ancestor_with_attributes(
        [ $VENDOR_ID_ATTRIBUTE, $PRODUCT_ID_ATTRIBUTE ]
    );
}

sub _path_attribute {
    my $self = shift;
    my $attribute = shift;
    my $path = shift || $self->path;
    
    my $pathobj = Path::Tiny->path($path, $attribute);
    
    IUGM::Error->throw("Unknown attribute name $attribute!")
        if ! $pathobj->exists;
    
    return $self->_read_attribute_value($pathobj);
}

# Read a single attribute value file
sub _read_attribute_value {
    my $pathobj = shift;
    
    my @lines = $pathobj->lines({'chomp' => 1, 'count' => 1});
    
    return $lines[0];
}

sub vpp {
    my $self = shift;

    my $vendor_id = lc $self->_path_attribute(
        $VENDOR_ID_ATTRIBUTE, $self->_device_root
    );
    my $product_id = lc $self->_path_attribute(
        $PRODUCT_ID_ATTRIBUTE, $self->_device_root
    );

    return IUGM::VendorProductPair->new(
        vendor_product_pair => (join q{:}, $vendor_id, $product_id),
    );
}

# Assumes our path has an $INTERFACE_NUMBER_ATTRIBUTE in it's path or an 
# ancestor's path
sub path_interface_number {
    my $self = shift;
    my $path = shift || $self->_ancestor_with_attributes(
        [ $INTERFACE_NUMBER_ATTRIBUTE ]
    );
    
    return $self->_read_attribute_value(
        Path::Tiny->path($path)->child($INTERFACE_NUMBER_ATTRIBUTE)
    );
}

sub configuration_value {
    my $self = shift;
    my $path = shift || $self->_ancestor_with_attributes(
        [ $CONFIGURATION_VALUE_ATTRIBUTE ]
    );
    
    my $configuration_value = $path->read_attribute_value(
        $CONFIGURATION_VALUE_ATTRIBUTE
    );
    
    $configuration_value =~ s/ ^ \D+ | \D+ $//xg;
    
    return $configuration_value * 1;
}

# Find the TTY associated with this interface
sub tty {
    my $self = shift;
    my $path = shift || $self->path;
    
    my $interface_ttys = Path::Tiny->path($path)->visit(
        sub {
            my ($filepath, $state) = @_;
            return if $filepath->basename !~ m/^ttyUSB\d+$/;
            $state->{$filepath->basename} = 1;
        }
    ); 

    # Guard against strange scenarios
    IUGM::Error->throw(q{No TTY's associated with this Sysfs path!})
        if keys %$interface_ttys == 0;
    IUGM::Error->throw(q{Multiple TTY's associated with this Sysfs path!})
        if keys %$interface_ttys > 1;
    
    return (keys %$interface_ttys)[0];
}

sub device_imei {
    my $self = shift;
    my $device = shift || $self->device;

    my $vpp = $self->vpp($device);
    my $control_interface_number = IUGM::Config->instance->device_control_interface_number($vpp);
   
    my $pathobj = Path::Tiny->path($self->path);
    my $configuration_value = $self->configuration_value($device);
    my $basename = $pathobj->basename;
    
    my $control_interface_pathobj = first {
        $_->child($INTERFACE_NUMBER_ATTRIBUTE)->exists
        && $self->read_attribute_value(
            $_->child($INTERFACE_NUMBER_ATTRIBUTE)
        ) == $control_interface_number
    } $pathobj->children(qr/ $basename : $configuration_value \. \d+ $/ix);

    IUGM::Error->throw('Could not find a control interface for ' . $self->path)
        if ! defined $control_interface_pathobj;

    # TODO: Clean this up after the accessors are cleaned up!    
    return IUGM::GSMModem->new(
        devnode => IUGM::Sysfs::Path(
            path => $control_interface_pathobj->stringify
        )->tty
    )->imei;
}

sub _ancestor_with_attributes {
    my $self = shift;
    my $attributes_aref = shift;
    my $path = shift || $self->path;
    
    my $ancestor = Path::Tiny->path($path);
    do {
        return $ancestor->stringify
            if scalar @attributes == scalar (grep {
               $ancestor->child($_)->exists
            } @attributes);
    
        $ancestor = $ancestor->parent;
    } while ($ancestor->stringify ne $self->_device_root);
    
    IUGM::Error->throw(
        q{Couldn't find an ancestor for }
        . $self->path
        . qq{ that contained the attribute(s): @attributes!}
    );
    
    return;
}

1;

__END__