#!/usr/bin/perl -T

# TODO:
# 1. Introduce the concept of logging and act appropriately based on how we are called (interactive or not)
# 2. Move grouped functions to object-oriented interfaces

# A program to identify USB sticks uniquely. Called by Udev rules!
#
# When a stick is plugged in, this script will be called once for each device file created.
# 1. If we know which port is the control interface for this device (by vendor/product)
# 2. Check to see if we've already polled this device for its IMEI.
# 3. If so, great. Read its IMEI from the cache.
# 4. If not, read its IMEI from the device, and store it in the cache.
#
# Called as:
# > identify-usb-gsm-modem.pl -p <udev_devpath> -n <udev_devnode>  -v<idVendor>:<idProduct> 
# i.e. identify-usb-gsm-modem.pl -p /sys/devices/platform/soc/3f98000.usb/usb1/1-1/1-1.4/1-1.4:1.0/ttyUSB0/tty/ttyUSB0 -n /dev/ttyUSB0 -v 12d1:1465
# Test with: > udevadm test /sys/devices/platform/soc/3f98000.usb/usb1/1-1/1-1.4/1-1.4:1.0/ttyUSB0/tty/ttyUSB0

# Extra info: in 1-2.3:4.5,
# the 1 is the id of the root hub
# the 2.3 is the port (.andnextport*)
# the 4 is the configuration number
# the 5 is the interface number

use Moo;
use MooX::Types::MooseLike::Base qw( :all );
use IUGM::Types;
with 'MooX::Getopt';
use IUGM::Config;
use IPC::Run qw( run );
use Path::Tiny;

option devpath => (
    is => 'ro',
    isa => Devpath,
    required => 1,
);

option devnode => (
    is => 'ro',
    isa => Devnode,
    required => 1,
);

option vpp => (
    is => 'ro'
    isa => VendorProductPair,
    required => 1,
);

has _config => (
    is => 'ro',
    isa => InstanceOf[ 'IUGM::Config' ],
    builder => 1,
);

sub _build__config {
    return IUGM::Config->new;
}


################################################################################
# Main #########################################################################
################################################################################

sub run {
    my $help;
    my $man;
    my $interface_devpath;
    my $interface_devnode;
    my $device_vendor_product_pair;

    GetOptions(
        'h|help' => \$help,
        'm|man' => \$man,
        'p|devpath=s' => \$interface_devpath,
        'n|devnode:s' => \$interface_devnode,
        'v|vendorproductpair:s' => \$device_vendor_product_pair
    ) or pod2usage(2);
    pod2usage(1) if $help;
    pod2usage(-exitval => 0, -verbose => 2) if $man;
    verify_options($interface_devpath, $interface_devnode, $device_vendor_product_pair);

    # Get the device's devpath
    my $device_devpath = get_device_devpath_for_interface($interface_devpath);

    # Get the device's vendor:product pair if it wasn't provided
    if (! defined $device_vendor_product_pair) {
        $device_vendor_product_pair = get_vendor_product_pair_for_device($device_devpath);
    }

    if (is_recognized_device($device_vendor_product_pair)) {
        my $imei = get_imei_for_device($device_devpath, $device_vendor_product_pair);
    
        my $device_alias = get_device_alias($imei);
    
        if (defined $device_alias) {
            my $interface_number = get_interface_number_for_interface($interface_devpath);
            my $interface_names = get_name_for_device_interface_number($device_vendor_product_pair, $interface_number);
        
            # A successful identification
            print $device_alias . '-' . $interface_names[0] . "\n";
        }
        else {
            die "Device with IMEI $imei has no alias. Check config file.\n";
        }
    }
    else {
        die "Device with vendor product pair $device_vendor_product_pair is not recognized.\n";
    }
}

################################################################################
# Options ######################################################################
################################################################################

# Verify the command line arguments
sub verify_options {
    my ($interface_devpath, $interface_devnode, $vendor_product_pair) = @_;

    if (! defined $interface_devpath) {
        die "The interface path must be specified!\n";
    }
    elsif (! -e $interface_devpath) {
        die "The interface path $interface_devpath does not exist!\n";
    }
    
    if (defined $interface_devnode && !-e $interface_devnode) {
        die "The interface node $interface_devnode does not exist!\n";
    }

    if (defined $vendor_product_pair && !is_valid_vendor_product_pair($vendor_product_pair)) {
        die "The vendor product pair $vendor_product_pair is not valid!\n";
    }
}

#
# Sysfs
#

# Retrieve the IMEI for the USB device containing the provided devpath
sub get_imei_for_device {
    my ($device_devpath, $vendor_product_pair) = @_;
    
    # Check cache first
    my @device_stats = stat $device_devpath;
    my $device_insertion_mtime = $device_stats[9];
    my $imei = cache_retrieve($device_devpath, $device_insertion_mtime);
    if (defined $imei) {
        if ($imei =~ m/^(\d{15})$/) {
            $imei = $1;
        }
        else {
            warn "Retrieved invalid IMEI from cache.\n";
            undef $imei;
        }
    }
    
    # If nothing was found in the cache, get the IMEI from the device's control
    # port, and store it in the cache.
    if (! defined $imei) {
        $imei = poll_device_for_imei($device_devpath, $vendor_product_pair);
        cache_store($device_devpath, $device_insertion_mtime, $imei);
    }
    
    return $imei;
}

=head1 NAME
identify-gsm-modem.pl - Identify USB GSM modems by their IMEI.
=head1 SYNOPSIS
identify-gsm-modem.pl [-h|--help] [--man] -p path [-n node] [-v vendor-product-pair]
 Options:
   -h|--help
                     brief help message
   -m|--man
                     full documentation
   -p|--devpath
                     specify the interface's path in (usually in /sys)
   -n|--devnode
                     specify the interface's mounted node (usually in /dev)
   -v|--vendor-product-pair
                     specify the device's vendor and product ids in hex:
                     e.g. 12d1:1465
                      
=head1 OPTIONS
=over 8
=item B<-help>
The help message hasn't been written yet :(
=item B<-man>
The man page hasn't been written yet :(
=back
=head1 DESCRIPTION
B<identify-gsm-modem.pl> will help you identify GSM Modems by their IMEI.
=cut