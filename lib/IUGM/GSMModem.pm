package IUGM::GSMModem;

use IUGM qw( $CONFIG_TEMP_DIR );

use Moo;
use IUGM::Types;
use IUGM::Config;
use Path::Tiny;
use Device::Modem;
use autodie;

our $VERSION = '0.01';

has devnode => (
    is => 'ro',
    isa => Devnode,
    required => 1,
);

has _lockfile_path => (
    is => 'ro',
    isa => Str,
    required => 1,
    builder => 1,
    lazy => 1,
);

sub _build__lockfile_path {
    return Path::Tiny->path(
        IUGM::Config->instance->val($CONFIG_TEMP_DIR),
        Path::Tiny->path($self->devnode)->basename . q{.lock}
    );
}

sub imei {
    my $self = shift;

    my $file_lock = IUGM::FileLock->new(
        lockfile => $self->_lockfile_path
    )->lock_ex;

    # Ask the device for its IMEI
    my $answer;
    my $modem = Device::Modem->new( 'port' => $self->devnode );
    if ($modem->connect( baudrate => 9600 )) {
        $modem->atsend('ATi1' . Device::Modem::CR);
        $answer = $modem->answer();
        $modem->disconnect();
    }
    else {
        IUGM::Error->throw(
            q{Failed to connect to USB device at } . $self->devnode
        );
    }
    
    $file_lock->unlock;

    # Process the modem response
    IUGM::Error->throw("No answer from USB device!")
        if ! defined $answer;
    IUGM::Error->throw("Unexpected response from USB device: $answer")
        if $answer !~ m/IMEI: (\d{15})/im;   
    return $1;
}

=head1 NAME

IUGM::Modem - The great new IUGM::Modem!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use IUGM::Modem;

    my $foo = IUGM::Modem->new();
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

    perldoc IUGM::Modem


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

1; # End of IUGM::Modem
