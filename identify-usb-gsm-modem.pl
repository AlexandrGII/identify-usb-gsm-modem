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

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use Config::Tiny;
use Device::Modem;
use IPC::Run qw( run );
use Path::Tiny;
use Fcntl qw( :flock );
use DBI;

# Potentially reasonable user config
my @config_file_locations = (
    '/etc/identify-usb-gsm-modem.conf'
);
my %config_defaults = (
    'temp_dir' => '/tmp',
    'cache_filepath' => '/tmp/identify-usb-gsm-modem.cache',
    'cache_lock_filepath' => '/tmp/identify-usb-gsm-modem.lock',
    'cache_table_name' => 'gsm_modem_imei',
);
# End potentially reasonable user config

################################################################################
# Main #########################################################################
################################################################################

my %CONFIG = %config_defaults;
go();
exit;

sub go {
    my $help;
    my $man;
    my $interface_devpath;
    my $interface_devnode;
    my $device_vendor_product_pair;

    setup_config();

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
            my @interface_names = get_names_for_device_interface_number($device_vendor_product_pair, $interface_number);
        
            if (@interface_names == 0) {
                die "Interface $interface_number is unknown for device $device_vendor_product_pair. Check config file.\n";
            }
            elsif (@interface_names > 1) {
                die "Interface $interface_number has multiple names for device $device_vendor_product_pair. Check config file.\n";
            }
            else {
                # A successful identification
                print $device_alias . '-' . $interface_names[0] . "\n";
            }
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

################################################################################
# Config Setup #################################################################
################################################################################

# Establish the program config by establishing sensible defaults and overwriting
# and/or adding values from the configuration file. 
sub setup_config {
    my $config_file = find_config_file();
    if (defined $config_file) {
        verify_config_file_eligibility($config_file);
        my $config_file_data = Config::Tiny->read($config_file,'utf8');
        merge_config_file_into_program_config($config_file_data);
    }
}

# Iterate through the provided config file locations and select the first one.
sub find_config_file {
    foreach my $config_filepath (@config_file_locations) {
        if (-e $config_filepath) {
            return $config_filepath;
        }
    }
    
    die "Failed to find a config file at any of the regular locations:\n" . join("\t\n", @config_file_locations) . "\n";
}

# Make sure we can access the config file
sub verify_config_file_eligibility {
    my $config_file = shift;
    
    if (! -f $config_file) {
        die "The configuration file at $config_file isn't a real file!\n";
    }
    if (! -r $config_file) {
        die "The configuration file at $config_file isn't readable to the current user!\n";
    }
}

# Merge the config file values into the program config
sub merge_config_file_into_program_config {
    my $config_file_data = shift;
    foreach my $section (keys %$config_file_data) {
        $section = lc $section;
        
        # Don't process root-level values
        next if $section eq '_';
        
        # Process the General section
        if ($section eq 'general') {
            foreach my $name (keys %{ $config_file_data->{$section} }) {
                $CONFIG{$name} = $config_file_data->{$section}->{$name};
            }
        }
        
        # Process a vendor-product pair
        elsif ($section =~ m/ ^ [0-9a-f]{4} : [0-9a-f]{4} $ /iox) {
            if (! exists $CONFIG{'known_vendor_product_pairs'} ) {
                $CONFIG{'known_vendor_product_pairs'} = {};
            }
            if (! exists $CONFIG{'known_vendor_product_pairs'}{$section}) {
                $CONFIG{'known_vendor_product_pairs'}{$section} = {};
            }
            
            foreach my $name (keys %{ $config_file_data->{$section} }) {
                $CONFIG{'known_vendor_product_pairs'}{$section}{$name} = $config_file_data->{$section}->{$name};
            }
            
            if (! exists $CONFIG{'known_vendor_product_pairs'}{$section}{'control'}) {
                die "Device $section must have a control interface specified in the config file!\n";
            }
        }
        
        # Process the devices section
        elsif ($section eq 'devices') {
            if (! exists $CONFIG{'known_imei'}) {
                $CONFIG{'known_imei'} = {};
            }
            
            foreach my $name (keys %{ $config_file_data->{$section} }) {
                if ($name =~ m/ ^ (\d{15}) $ /iox) {
                    $CONFIG{'known_imei'}{$name} = $config_file_data->{$section}->{$name};
                
                    my $imei = $1;
                }
                else {
                    die "Value $name in [devices] section is invalid format for an IMEI!\n";
                }
            }
        }
        
        # Section name is unknown
        else {
            die "Unknown section [$section] in the configuration file!\n";
        }
    }
}

################################################################################
# Config Accessors #############################################################
################################################################################

sub get_config_directive {
    my $directive = shift;
    
    if (exists $CONFIG{$directive}) {
        return $CONFIG{$directive};
    }
    
    die "$directive config directive was not configured in the program or config file!\n";
}

sub get_temp_dir {
    return get_config_directive('temp_dir');
}

sub get_cache_filepath {
    return get_config_directive('cache_filepath');
}

sub get_cache_lock_filepath {
    return get_config_directive('cache_lock_filepath');
}

sub get_cache_table_name {
    if (exists $CONFIG{'cache_table_name'}) {
        return $CONFIG{'cache_table_name'};
    }
    
    die "cache_table_name config directive was not configured in program or config file!\n";
}

# Determine if we have a record of this vendor:product combination
sub is_recognized_device {
    my $vendor_product_pair = shift;
   
    if (exists $CONFIG{'known_vendor_product_pairs'}
        && exists $CONFIG{'known_vendor_product_pairs'}{$vendor_product_pair}
    ) {
        return 1;
    }
    
    return 0;
}

# Check the config for known IMEI's alias
sub get_device_alias {
    my $imei = shift;
    
    if (exists $CONFIG{'known_imei'}
        && exists $CONFIG{'known_imei'}{$imei}) {
        return $CONFIG{'known_imei'}{$imei};
    }
    
    return undef;
}

# Check the config for a device's interface names
sub get_names_for_device_interface_number {
    my ($vendor_product_pair, $interface_number) = @_;

    if (! is_recognized_device($vendor_product_pair)) {
        return;    
    }

    my @interface_names = grep {
        $CONFIG{'known_vendor_product_pairs'}{$vendor_product_pair}{$_} eq $interface_number
    } keys %{ $CONFIG{'known_vendor_product_pairs'}{$vendor_product_pair} };
    
    return @interface_names;
}

# Check the config for a device's control interface number
sub get_device_control_interface {
    my $vendor_product_pair = shift;
    
    if (! is_recognized_device($vendor_product_pair)) {
        return;    
    }
    
    if (! exists $CONFIG{'known_vendor_product_pairs'}{$vendor_product_pair}{'control'}) {
        return undef;
    }
    
    return $CONFIG{'known_vendor_product_pairs'}{$vendor_product_pair}{'control'};
}

################################################################################
# Sysfs ########################################################################
################################################################################

sub get_device_devpath_for_interface {
    my $interface_devpath = shift; # e.g. /sys/devices/platform/soc/3f98000.usb/usb1/1-1/1-1.4/1-1.4:1.0/ttyUSB0/tty/ttyUSB0
    
    # Look for a directory that contains files idVendor and idProduct
    my $device_devpath = find_devpath_ancestor_with_attributes($interface_devpath, 'idVendor', 'idProduct');
    
    return $device_devpath;
}

sub get_vendor_product_pair_for_device {
    my $device_devpath = shift;
    
    # idVendor
    my $idVendor = lc load_devpath_attribute($device_devpath, 'idVendor');
    
    # idProduct
    my $idProduct = lc load_devpath_attribute($device_devpath, 'idProduct');
    
    # Vendor:product pair
    my $vendor_product_pair = $idVendor . ':' . $idProduct;
    if (!is_valid_vendor_product_pair($vendor_product_pair)) {
        die "The interface's vendor product pair ($vendor_product_pair) is not valid!\n";
    }
    
    return $vendor_product_pair;
}

sub load_devpath_attribute {
    my ($devpath, $attribute_file_name) = @_;
    
    my $attribute_file_pathobj = path($devpath, $attribute_file_name);
    if ($attribute_file_pathobj->exists) {
        return read_attribute_value($attribute_file_pathobj);
    }
    else {
        die "Unknown attribute name $attribute_file_name!\n";
    }

    return undef;
}

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

# Determine the interface number for the tty devpath provided
sub get_interface_number_for_interface {
    my $interface_devpath = shift;
    
    my $devpath_ancestor = find_devpath_ancestor_with_attributes($interface_devpath, 'bInterfaceNumber');
    my $interface_number_file = path($devpath_ancestor)->child('bInterfaceNumber');
    
    return read_attribute_value($interface_number_file);
}

sub find_devpath_ancestor_with_attributes {
    my ($devpath, @attribute_files) = @_;
    
    my $ancestor_pathobj = path($devpath)->parent;
    while ($ancestor_pathobj->stringify ne Path::Tiny->rootdir) {
        my $all_found = 1;
        foreach my $attribute_file (@attribute_files) {
            my $testing_pathobj = $ancestor_pathobj->child($attribute_file);
            if (! $testing_pathobj->exists) {
                $all_found = 0;
                last;
            }
        }
        
        if ($all_found) {
            return $ancestor_pathobj->stringify;
        }
        
        $ancestor_pathobj = $ancestor_pathobj->parent;
    }
    
    die "Couldn't find an ancestor for $devpath that contained the attribute(s): @attribute_files!\n";
}

# Retrieve the IMEI from the device by asking it
sub poll_device_for_imei {
    my ($device_devpath, $vendor_product_pair) = @_;
    
    # Find the device's control devnode
    my $device_control_interface = get_device_control_interface($vendor_product_pair);
    if (! defined $device_control_interface) {
        die "A 'control' interface for device $vendor_product_pair is not configured. Check config file.\n";
    }
    
    my $device_pathobj = path($device_devpath);
    my $configuration_value = read_attribute_value($device_pathobj->child('bConfigurationValue'));
    $configuration_value = trim_to_digits($configuration_value) * 1;

    my $basename = $device_pathobj->basename;
    my @available_interface_pathobjs = $device_pathobj->children(qr/ $basename : $configuration_value \. \d+ $/iox);
    foreach my $available_interface_pathobj (@available_interface_pathobjs) {
        my $interface_number_pathobj = $available_interface_pathobj->child('bInterfaceNumber');
        if ($interface_number_pathobj->exists
            && read_attribute_value($interface_number_pathobj)
                == $device_control_interface
        ) {
            # This interface is the device's control devnode.
            my $control_tty = get_tty_for_interface( $available_interface_pathobj->stringify );
            return poll_devnode_for_imei( path('/dev', $control_tty)->stringify );
        }    
    }

    die "Could not find control devnode for device!\n";
}

# Read a single attribute value file
sub read_attribute_value {
    my $pathobj = shift;
    
    my @lines = $pathobj->lines({'chomp' => 1, 'count' => 1});
    
    return $lines[0];
}

# Expect padded digits, return unpadded digits
sub trim_to_digits {
    my $value = shift;
    $value =~ s/(?:^\D+|\D+$)//g;
    return $value;
}

# Find the TTY associated with this interface
sub get_tty_for_interface {
    my $interface_devpath = shift;

    my $interface_ttys = path($interface_devpath)->visit(
        sub {
            my ($path, $state) = @_;
            return if $path->basename !~ m/^ttyUSB\d+$/;
            $state->{$path->basename} = 1;
        }
    ); 
            
    # Guard against strange scenarios
    if (keys %$interface_ttys == 0) {
        die "No TTY's associated with this device interface!\n";
    }
    elsif (keys %$interface_ttys > 1) {
        die "Multiple TTY's associated with this device interface!\n";
    }
    
    return (keys %$interface_ttys)[0];
}

################################################################################
# Comm #########################################################################
################################################################################

# Actually poll a device for its IMEI
sub poll_devnode_for_imei {
    my $devnode = shift; # e.g. /dev/ttyUSB0

    # Acquire a lock for accessing this devnode    
    my $temp_dir = get_temp_dir();
    my $devnode_lockfile = path($temp_dir, path($devnode)->basename . '.lock');
    open (my $devnode_lock, '>>', $devnode_lockfile)
        or die "Couldn't open the devnode lockfile at $devnode_lockfile!\n";
    flock($devnode_lock, LOCK_EX)
        or die "Coudln't lock the devnode lockfile exclusively!\n";

    # Ask the device for its IMEI
    my $answer = undef;
    my $modem = new Device::Modem( 'port' => $devnode );
    if ($modem->connect( baudrate => 9600 )) {
        $modem->atsend('ATi1' . Device::Modem::CR);
        $answer = $modem->answer();
        $modem->disconnect();
    }
    else {
        die "Failed to connect to USB device at $devnode!\n";
    }
    
    # Release the lock
    flock($devnode_lock, LOCK_UN)
        or die "Couldn't unlock the devnode lockfile!\n";
    close($devnode_lock);
    
    # Process the modem response
    if (defined $answer && $answer =~ /IMEI: (\d{15})/imo) {
        return $1;
    }
    elsif (defined $answer) {
        die "Unexpected response from USB device: $answer\n";
    }
    else {
        die "No answer from USB device!\n";
    }
}

################################################################################
# Cache ########################################################################
################################################################################

# Returns undef if a value wasn't found, or, the value found was null
sub cache_retrieve {
    my ($device_devpath, $device_insertion_mtime) = @_;

    my $cache_value = undef;

    # Quick check
    my $cache_filepath = get_cache_filepath();
    if (! -e $cache_filepath) {
        return undef;
    }
    
    my $cache_table_name = get_cache_table_name();
    my $dbh = db_open();
    if (db_imei_table_exists($dbh)) {
        # Expire any entries
        my $sth = $dbh->prepare(qq{
            DELETE
            FROM $cache_table_name
            WHERE device_devpath = ? AND device_insertion_mtime != ?
        });
        $sth->execute($device_devpath, $device_insertion_mtime);
    
        # Read from the table
        $sth = $dbh->prepare(qq{
            SELECT imei
            FROM $cache_table_name
            WHERE device_devpath = ? AND device_insertion_mtime = ?
        });
        $sth->execute($device_devpath, $device_insertion_mtime);
        
        if (my @row = $sth->fetchrow_array) {
            $cache_value = $row[0];
        }
    }
    
    db_close($dbh);
    
    return $cache_value;
}

sub cache_store {
    my ($device_devpath, $device_insertion_mtime, $imei) = @_;
        
    my $cache_table_name = get_cache_table_name();
    
    my $dbh = db_open();
    if (! db_imei_table_exists($dbh)) {
        db_create_imei_table($dbh);
    }

    # Store our value
    my $sth = $dbh->prepare(qq{
        INSERT INTO $cache_table_name
        (device_devpath, device_insertion_mtime, imei)
        VALUES (?, ?, ?)
    });
    $sth->execute($device_devpath, $device_insertion_mtime, $imei);
    
    db_close($dbh);
}

sub db_open {
    my $cache_lock_filepath = get_cache_lock_filepath();
    my $cache_filepath = get_cache_filepath();

    # Implement a lock to prevent two processes from creating the database at the same time
    open(my $lockfile, '>>', $cache_lock_filepath)
        or die "Couldn't open cache lockfile!\n";
    flock($lockfile, LOCK_EX)
        or die "Couldn't lock cache lockfile!\n";

    my $dbh = DBI->connect("dbi:SQLite:dbname=$cache_filepath", undef, undef, {
        'AutoCommit' => 1,
        'RaiseError' => 1,
        'sqlite_see_if_its_a_number' => 1,
    });
    
    flock($lockfile, LOCK_UN);
    close($lockfile);
    
    return $dbh;
}

sub db_close {
    my $dbh = shift;
    
    $dbh->disconnect;
}

sub db_imei_table_exists {
    my $dbh = shift;
    
    my $cache_table_name = get_cache_table_name();
    
    # Has the table been created?
    my $sth = $dbh->prepare(q{
        SELECT 1 FROM sqlite_master WHERE type='table' AND name LIKE ?;
    });
    $sth->execute($cache_table_name);
    if (my @row = $sth->fetchrow_array) {
        $sth->finish;
        return 1;
    }
    
    return 0;
}

sub db_create_imei_table {
    my $dbh = shift;
    
    my $cache_table_name = get_cache_table_name();
    
    # Create the table
    my $sth = $dbh->prepare(qq{
        CREATE TABLE IF NOT EXISTS $cache_table_name (
            device_devpath VARCHAR(255) NOT NULL,
            device_insertion_mtime INT(11) NOT NULL,
            imei INT(15) NOT NULL,
            PRIMARY KEY (device_devpath, device_insertion_mtime)
        )
    });
    $sth->execute;
}

################################################################################
# Utility ######################################################################
################################################################################
sub is_valid_vendor_product_pair {
    my $vendor_product_pair = shift;
    if ($vendor_product_pair =~ m/ ^ [0-9a-f]{4} : [0-9a-f]{4} $ /iox) {
        return 1;
    }
    return 0;
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