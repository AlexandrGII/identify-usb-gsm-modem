#!/usr/bin/perl -Ilib

use Modern::Perl;

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

package IdentifyUSBGSMModem {

    use Moo;
    use MooX::Options;
    use MooX::Types::MooseLike::Base qw( :all );
    use Types::Path::Tiny qw( Path );
    use Path::Tiny;
    use IUGM::Config;
    use IUGM::SysfsPath;
    use IUGM::VendorProductPair;
    use IUGM::GSMModemInterface;
    use IUGM::DeviceCache;
    use IUGM::Error;
    use IUGM::PriorityLogger;
    use autodie;

    option devnode => (
        is => 'ro',
        isa => Path,
        required => 1,
        order => 1,
        short => 'n',
        format => 's',
        doc => 'specify the udev devnode',
    );

    option devpath => (
        is => 'ro',
        isa => InstanceOf[ 'IUGM::SysfsPath' ],
        required => 1,
        order => 2,
        short => 'p',
        format => 's',
        doc => 'specify the udev devpath',
    );

    option vpp => (
        is => 'ro',
        isa => Str,
        predicate => 1,
        order => 3,
        short => 'v',
        format => 's',
        doc => 'specify the modem vendor:product pair',
    );
    
    option logfile => (
        is => 'ro',
        isa => Str,
        predicate => 1,
        order => 4,
        short => 'l',
        format => 's',
        doc => 'specify a path to log events',
    );

    has _config => (
        is => 'ro',
        isa => InstanceOf[ 'IUGM::Config' ],
        builder => 1,
    );
    
    has _gsm_modem_interface => (
        is => 'ro',
        isa => InstanceOf[ 'IUGM::GSMModemInterface' ],
        builder => 1,
        lazy => 1,
    );
    
    has _device_cache => (
        is => 'ro',
        isa => InstanceOf[ 'IUGM::DeviceCache' ],
        builder => 1,
        lazy => 1,
    );
    
    has _logger => (
        is => 'ro',
        isa => InstanceOf[ 'IUGM::PriorityLogger' ],
        builder => 1,
    );

    # Convert the string arguments into their object equivalents
    sub BUILDARGS {
        my ($class, %args) = @_;

        $args{devpath} = IUGM::SysfsPath->new( path => $args{devpath} )
            if exists $args{devpath};

        $args{devnode} = path($args{devnode})
            if exists $args{devnode};

        if (exists $args{vpp}) {
            my %vpp_args;
            @vpp_args{qw(vendor_id product_id)} = split q{:}, $args{vpp};
            $args{vpp} = IUGM::VendorProductPair->new( %vpp_args )->stringify;
        }        
    
        return \%args;
    }

    sub _build__config {
        return IUGM::Config->instance;
    }
    
    sub _build__gsm_modem_interface {
        my $self = shift;
        
        return IUGM::GSMModemInterface->new(
            interface_sysfs_path => $self->devpath,
            interface_devnode => $self->devnode,
            ($self->has_vpp ? (vpp => $self->vpp) : ())
        );
    }
    
    sub _build__device_cache {
        return IUGM::DeviceCache->new;
    }
    
    sub _build__logger {
        my $self = shift;

        return IUGM::PriorityLogger->instance(
            logfile => $self->has_logfile
                ? $self->logfile
                : $self->_config->val('logfile')
        );
    }

    sub run {
        my $self = shift;

        my %command_line_options = $self->_command_line_options;
        $self->_logger->log_event(
            qq{Run started:\n\t}
                . (join "\n\t", map {
                    $_ . ': ' . $command_line_options{$_}
                } keys %command_line_options)
        );

        my $identity = $self->_identify_usb_gsm_modem;
        
        $self->_logger->log_event(q{Run ended});
        
        die "Unknown USB GSM Modem" if ! defined $identity;
        
        print $identity, "\n";
        
        return;
    }
    
    sub _command_line_options {
        my $self = shift;
        
        my %command_line_options;
        
        $command_line_options{devnode} = $self->devnode;
        $command_line_options{devpath} = $self->devpath->path->stringify;
        $command_line_options{vpp} = $self->vpp
            if $self->has_vpp;
        $command_line_options{logfile} = $self->logfile
            if $self->has_logfile;
        
        return %command_line_options;
    }

    sub _identify_usb_gsm_modem {
        my $self = shift;

        $self->_logger->log_info(
            q{Device VPP: } . $self->_gsm_modem_interface->vpp
        );

        if ($self->_config->is_known_vpp($self->_gsm_modem_interface->vpp)) {
            $self->_logger->log_info(
                q{VPP found in configuration}
            );
            
            my $imei = $self->device_imei;
            $self->_logger->log_info(qq{IMEI: $imei});
            
            my $imei_alias = $self->_config->imei_alias($imei)
                or IUGM::Error->throw("Unknown IMEI: $imei");
            $self->_logger->log_info(qq{IMEI Alias: $imei_alias});
                
            my $name = $self->_config->device_interface_name(
                $self->_gsm_modem_interface->vpp,
                $self->_gsm_modem_interface->interface_number
            );
            
            if (defined $name) {
                $self->_logger->log_info(qq{Interface: $name});
                return join '-', $imei_alias, $name;
            }
            else {
                $self->_logger->log_info(qq{Interface name unknown});
            }
        }
        else {
            $self->_logger->log_info(
                q{VPP not found in configuration}
            );
        }
        
        return;
    }

    sub device_imei {
        my $self = shift;

        # First, check the cache        
        my $device_inserted = $self->devpath->path->stat->[9];
        my $imei = $self->_device_cache
            ->retrieve($self->devpath, $device_inserted);
        $self->_logger->log_info(
            q{IMEI} . (defined $imei ? q{ } : q{ not }) . q{found in cache}
        );

        # If nothing was found in the cache, poll the device for the IMEI
        # and store it in the cache.
        if (! defined $imei) {
            $imei = $self->_gsm_modem_interface->device_imei;
            $self->_device_cache
                ->store($self->devpath, $device_inserted, $imei);
        }

        return $imei;
    }

    1;
}

IdentifyUSBGSMModem->new_with_options->run;

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