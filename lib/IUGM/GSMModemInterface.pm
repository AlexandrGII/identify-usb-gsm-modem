package IUGM::GSMModemInterface;

use Moo;
use MooX::Types::MooseLike::Base qw( :all );
use Types::Path::Tiny qw( Path );
use IUGM::SysfsPath;
use IUGM::Config;
use Path::Tiny;
use Readonly;
use IUGM::Error;
use IUGM::GSMModemControlTTY;

our $VERSION = '0.01';

Readonly my $VENDOR_ID_ATTRIBUTE => 'idVendor';
Readonly my $PRODUCT_ID_ATTRIBUTE => 'idProduct';
Readonly my $INTERFACE_NUMBER_ATTRIBUTE => 'bInterfaceNumber';
Readonly my $CONFIGURATION_VALUE_ATTRIBUTE => 'bConfigurationValue';

has interface_sysfs_path => (
    is => 'ro',
    isa => InstanceOf[ 'IUGM::SysfsPath' ],
    required => 1,
);

has interface_devnode => (
    is => 'ro',
    isa => Path,
    required => 1,
);

has device_sysfs_path => (
    is => 'ro',
    isa => InstanceOf[ 'IUGM::SysfsPath' ],
    builder => 1,
    lazy => 1,
);

has vpp => (
    is => 'ro',
    isa => Str,
    builder => 1,
    lazy => 1,
);

# Convert provided Sysfs Path attributes to IUGM::SysfsPath objects
sub BUILDARGS {
    my ($class, %args) = @_;
 
    foreach my $sysfs_path_arg (qw(interface_sysfs_path device_sysfs_path)) {
        if (exists $args{$sysfs_path_arg} && defined $args{$sysfs_path_arg}) {
            # Convert string paths to IUGM::SysfsPath objects         
            if (ref $args{$sysfs_path_arg} eq ''
                && length $args{$sysfs_path_arg}) {
                $args{$sysfs_path_arg} = IUGM::SysfsPath->new(
                    path => path($args{$sysfs_path_arg})
                );
            }
            # Convert Path::Tiny instances to IUGM::SysfsPath objects
            elsif (ref $args{$sysfs_path_arg} eq 'Path::Tiny') {
                $args{$sysfs_path_arg} = IUGM::SysfsPath->new(
                    path => $args{$sysfs_path_arg}
                );
            }
        }
    }

    return \%args;   
}

sub _build_device_sysfs_path {
    my $self = shift;
    
    return $self->interface_sysfs_path->ancestor_with_attributes(
        $VENDOR_ID_ATTRIBUTE, $PRODUCT_ID_ATTRIBUTE
    );
}

sub _build_vpp {
    my $self = shift;

    return lc IUGM::VendorProductPair->new(
        vendor_id => lc $self->device_sysfs_path->attribute($VENDOR_ID_ATTRIBUTE),
        product_id => lc $self->device_sysfs_path->attribute($PRODUCT_ID_ATTRIBUTE)
    )->stringify;
}

sub interface_number {
    my $self = shift;
    
    return $self
        ->interface_sysfs_path
        ->ancestor_with_attributes($INTERFACE_NUMBER_ATTRIBUTE)
        ->attribute($INTERFACE_NUMBER_ATTRIBUTE);
}

sub configuration_value {
    my $self = shift;
    
    my $configuration_value = $self
        ->device_sysfs_path
        ->attribute($CONFIGURATION_VALUE_ATTRIBUTE);
    
    $configuration_value =~ s/ ^ \D+ | \D+ $//xg;
    
    return $configuration_value * 1;
}

sub device_imei {
    my $self = shift;

    return IUGM::GSMModemControlTTY->new(
        devnode => $self->_device_control_interface_devnode
    )->imei;
}

sub _device_control_interface_devnode {
    my $self = shift;
    
    my $device_control_interface_sysfs_path
        = $self->_device_control_interface_sysfs_path;
    
    my @ttyUSBs = $self
        ->_device_control_interface_sysfs_path
        ->path
        ->children(
            qr/ ^ ttyUSB \d+ $ /x
        );

    IUGM::Error->throw(q{No TTY's associated with }
         . $device_control_interface_sysfs_path->path
    ) if @ttyUSBs == 0;
    IUGM::Error->throw(q{Multiple TTY's associated with }
        . $device_control_interface_sysfs_path->path
    ) if @ttyUSBs > 1;
    
    return path('/dev')->child($ttyUSBs[0]->basename);
}

sub _device_control_interface_sysfs_path {
    my $self = shift;
    
    my $configured_control_interface_number = 
        IUGM::Config->instance->device_control_interface_number($self->vpp);
    
    my $control_interface_basename = sprintf("%s:%d.%d",
        $self->device_sysfs_path->path->basename,
        $self->configuration_value,
        $configured_control_interface_number
    );
    my $control_interface_path = $self
        ->device_sysfs_path
        ->path
        ->child($control_interface_basename);

    IUGM::Error->throw('Could not find a control interface for ' . $self->path)
        if ! $control_interface_path->exists;
    
    return IUGM::SysfsPath->new(
        path => $control_interface_path
    );    
}

1;