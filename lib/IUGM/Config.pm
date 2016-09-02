package IUGM::Config;

use Moo;
with 'MooX::Singleton';
use MooX::Types::MooseLike::Base qw( :all );
use IUGM::Types qw( ReadableFile );
use Config::Tiny;
use Storable qw( dclone );
use Readonly;
use IUGM::Error;

our $VERSION = '0.01';

Readonly::Hash my %CONFIG_DEFAULTS => (
    temp_dir => '/tmp',
    cache_filepath => '/tmp/identify-usb-gsm-modem.cache',
    cache_lock_filepath => '/tmp/identify-usb-gsm-modem.lock',
    logfile => '/tmp/identify-usb-gsm-modem.log',
);
Readonly my $SECTION_VPP => 'known_vendor_product_pairs';
Readonly my $SECTION_IMEI => 'known_imei';
Readonly my $CONTROL_INTERFACE_NAME => 'control';

has config_file => (
    is => 'ro',
    isa => ReadableFile,
    builder => 1,
);

has _sensible_defaults => (
    is => 'ro',
    isa => HashRef,
    builder => 1,
);

has _config => (
    is => 'ro',
    isa => HashRef,
    builder => 1,
    lazy => 1,
);

sub _build_config_file {
    return '/etc/identify-usb-gsm-modem.conf';
}

sub _build__config {
    my $self = shift;

    my $config = $self->_readfile;
    $self->_add_sensible_defaults($config);

    return $config;
}

sub _readfile {
    my $self = shift;
    
    my $file_conf = Config::Tiny->read($self->config_file, 'utf8');

    my %config;
    foreach my $section (keys %$file_conf) {       
        # Don't process root-level values
        next if $section eq '_';
        
        my $lc_section = lc $section;
        
        # Process the General section
        if ($lc_section eq 'general') {
            $self->_readfile_general(
                \%config,
                $file_conf->{$section}
            );
        }
        # Process a vendor-product pair
        elsif ($lc_section =~ m/ ^ [0-9a-f]{4} : [0-9a-f]{4} $ /x) {
            $self->_readfile_vpp(
                \%config,
                $lc_section,
                $file_conf->{$section}
            );
        }
        # Process the devices section
        elsif ($lc_section eq 'devices') {
            $self->_readfile_devices(
                \%config,
                $file_conf->{$section}
            );
        }
        # Section name is unknown
        else {
            die "Unknown section [$section] in the configuration file!\n";
        }
    }
    
    return \%config;    
}

sub _add_sensible_defaults {
    my $self = shift;
    my $config = shift;
    
    foreach my $key (keys %{ $self->_sensible_defaults }) {
        $config->{$key} = $self->_sensible_defaults->{$key}
            if ! exists $config->{$key};
    }
}

sub _readfile_general {
    my $self = shift;
    my $config = shift;
    my $section = shift;
    
    @{$config}{keys %{$section}} = values %{$section};
    
    return $self;
}

sub _readfile_vpp {
    my $self = shift;
    my $config = shift;
    my $section_name = shift;
    my $section = shift;

    # Vivify data structure
    $config->{$SECTION_VPP} = {}
        if ! exists $config->{$SECTION_VPP};
    $config->{$SECTION_VPP}->{$section_name} = {}
        if ! exists $config->{$SECTION_VPP}->{$section_name};
    
    # Deep copy
    $config->{$SECTION_VPP}->{$section_name} = dclone($section);

    # Sanity check
    die "Device $section_name must have a control interface specified in the config file!\n"
        if ! exists $config->{$SECTION_VPP}->{$section_name}->{$CONTROL_INTERFACE_NAME};
            
    return $self;
}

sub _readfile_devices {
    my $self = shift;
    my $config = shift;
    my $section = shift;    

    # Vivify data structure    
    $config->{$SECTION_IMEI} = {}
        if ! exists $config->{$SECTION_IMEI};

    # Check and copy each imei
    foreach my $imei (keys %{$section}) {
        if ($imei =~ m/ ^ (\d{15}) $ /ix) {
            $config->{$SECTION_IMEI}->{$imei} = $section->{$imei};
        }
        else {
            IUGM::Error->throw("Value $imei in [devices] section is not a valid IMEI!");
        }
    }

    return $self;
}

sub _build__sensible_defaults {
    return \%CONFIG_DEFAULTS;
}

sub val {
    my $self = shift;
    my $val = shift;
    
    IUGM::Error->throw("$val is not in the config!")
        if ! exists $self->_config->{$val};
        
    return $self->_config->{$val};
}

# Determine if we have a record of this vendor:product combination
sub is_known_vpp {
    my $self = shift;
    my $vendor_product_pair = shift;

    return 1 if exists $self->_config->{$SECTION_VPP}
        && exists $self->_config->{$SECTION_VPP}->{$vendor_product_pair};

    return 0;
}

# Check the config for known SECTION_IMEI's alias
sub imei_alias {
    my $self = shift;
    my $imei = shift;
    
    return $self->_config->{$SECTION_IMEI}->{$imei}
        if exists $self->_config->{$SECTION_IMEI}
        && exists $self->_config->{$SECTION_IMEI}->{$imei};

    return undef;
}

# Check the config for a device's interface name
sub device_interface_name { # get_names_for_device_interface_number
    my $self = shift;
    my $vendor_product_pair = shift;
    my $interface_number = shift;
    
    # Sanity check
    return if ! $self->is_known_vpp($vendor_product_pair);

    # Determine the interface name
    my $device = $self->_config->{$SECTION_VPP}->{$vendor_product_pair};
    my @interface_names = grep { $device->{$_} eq $interface_number} keys %{$device};
    
    # More sanity checks
    IUGM::Error->throw(
        "No name found for interface $interface_number on $vendor_product_pair"
    ) if @interface_names == 0;
    IUGM::Error->throw(
        "Duplicate interface names for interface number $interface_number on $vendor_product_pair"
    ) if @interface_names > 1;

    return $interface_names[0];
}

# Check the config for a device's control interface number
sub device_control_interface_number {
    my $self = shift;
    my $vendor_product_pair = shift;

    IUGM::Error->throw("$vendor_product_pair does not have a configured control interface")
        if ! $self->is_known_vpp($vendor_product_pair)
        || ! exists $self->_config->{$SECTION_VPP}->{$vendor_product_pair}->{$CONTROL_INTERFACE_NAME};

    return $self->_config->{$SECTION_VPP}->{$vendor_product_pair}->{$CONTROL_INTERFACE_NAME};
}



=head1 NAME

IUGM::Config - The great new IUGM::Config!

=head1 VERSION

Version 0.01

=cut

=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use IUGM::Config;

    my $foo = IUGM::Config->new();
    ...

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 SUBROUTINES/METHODS

=head2 function1

=cut

sub function1 {
}

=head2 function2

=cut

sub function2 {
}

=head1 AUTHOR

Patrick Cronin, C<< <patrick at cronin-tech.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-iugm at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=IUGM>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc IUGM::Config


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=IUGM>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/IUGM>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/IUGM>

=item * Search CPAN

L<http://search.cpan.org/dist/IUGM/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2016 Patrick Cronin.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

1; # End of IUGM::Config
