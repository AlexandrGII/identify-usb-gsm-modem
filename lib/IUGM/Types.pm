package IUGM::Types;

use Modern::Perl;
use Sub::Quote qw( quote_sub );
use Exporter qw( import );

our $VERSION = '0.01';

our @EXPORT_OK = qw(
  ReadableFile
  VendorID
  ProductID
  Devnode
  SysfsPath
);
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

## no critic (Capitalization)
sub ReadableFile () {
## use critic
    ## no critic (RequireInterpolationOfMetachars, ProhibitImplicitNewlines)
    return quote_sub(
        q{ IUGM::Error->throw(
            message => $_[0] . " is not a readable file",
            type => 'ReadableFile',
            value => $_[0]
           )
            unless defined $_[0]
            && -e $_[0]
            && -f $_[0]
            && -r $_[0];
        }
    );
    ## use critic
}

## no critic (Capitalization)
sub VendorID () {
## use critic
    ## no critic (RequireInterpolationOfMetachars, ProhibitImplicitNewlines)
    return quote_sub(
        q{
            IUGM::Error->throw(
                message => $_[0] . " is not a valid vendor id",
                type => 'VendorID',
                value => $_[0]
            )
            unless defined $_[0]
            && $_[0] =~ m/ ^ [0-9a-f]{4} $ /x;
        }
    );
    ## use critic
}

## no critic (Capitalization)
sub ProductID () {
## use critic
    ## no critic (RequireInterpolationOfMetachars, ProhibitImplicitNewlines)
    return quote_sub(
        q{
            IUGM::Error->throw(
                message => $_[0] . " is not a valid product id",
                type => 'ProductID',
                value => $_[0]
            )
            unless defined $_[0]
            && $_[0] =~ m/ ^ ([0-9a-f]{4}) $ /x;
        }
    );
    ## use critic
}

## no critic (Capitalization)
sub Devnode () {
## use critic
    ## no critic (RequireInterpolationOfMetachars, ProhibitImplicitNewlines)
    return quote_sub(
        q{
            IUGM::Error->throw(
                message => $_[0] . " is not a readable Devnode",
                type => 'Devnode',
                value => $_[0],
            )
            unless defined $_[0]
            && -e $_[0]
            && -c $_[0]
            && -r $_[0];
        }
    );
    ## use critic
}

## no critic (Capitalization)
sub SysfsPath () {
## use critic
    ## no critic (RequireInterpolationOfMetachars, ProhibitImplicitNewlines)
    return quote_sub(
        q{
            IUGM::Error->throw(
                message => $_[0] . " is not a readable Sysfs path",
                type => 'SysfsDevpath',
                value => $_[0],
            )
            unless defined $_[0]
            && -e $_[0]
            && -f $_[0]
            && -r $_[0];
        }
    );
    ## use critic
}

1;

__END__

=head1 NAME

IUGM::Types - Attribute types for the IUGM distribution

=head1 VERSION

Version 0.02

=head1 SYNOPSIS

Defines types for use in Moo-based classes.

    use strict;
    use warnings;

    use Moo;
    use IUGM::Types qw( ReadableFile );
    
    has config_file => (
        is => 'ro',
        isa => ReadableFile,
        required => 1,
    );

    ...

=head1 EXPORTS

=head2 ReadableFile

  Checks if the attribute exists, is a file, and is readable to the current user.

=head2 :all

  A tag that exports all types.

=head1 AUTHOR

Patrick Cronin, C<< <patrick at cronin-tech.com> >>

=head1 ACKNOWLEDGEMENTS

This class is heavily inspired from L<https://www.maxmind.com|MaxMind>'s
L<GeoIP2::Types|GeoIP2::Types> class.

=head1 BUGS

Please report any bugs or feature requests to C<patrick at cronin-tech.com>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc IUGM::Types

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
