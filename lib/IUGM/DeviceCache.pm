package IUGM::DeviceCache;

use IUGM qw( $CONFIG_CACHE_FILEPATH $CONFIG_CACHE_LOCK_FILEPATH );

use Moo;
use IUGM::Config;
use IUGM::FileLock;
use DBI;

our $VERSION = '0.01';

has _dbh => (
    is => 'ro',
    isa => InstanceOf[ 'DBI' ],
    builder => 1,
    lazy => 1,
);

sub _build__dbh {
    my $self = shift;

    # Implement a lock to prevent two processes from creating the database at the same time    
    my $filelock = IUGM::FileLock->new(
        lockfile => $CONFIG_CACHE_LOCK_FILEPATH
    )->lock_ex;

    my $dbh = DBI->connect("dbi:SQLite:dbname=$CONFIG_CACHE_FILEPATH", undef, undef, {
        'AutoCommit' => 1,
        'RaiseError' => 1,
        'sqlite_see_if_its_a_number' => 1,
    });
    
    $filelock->unlock;

    return $dbh;
}

sub DEMOLISH {
    if ($self->_dbh) {
        $self->_dbh->disconnect;
    }
}

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

=head1 NAME

IUGM::Cache - The great new IUGM::Cache!

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use IUGM::Cache;

    my $foo = IUGM::Cache->new();
    ...

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 SUBROUTINES/METHODS

=head1 AUTHOR

Patrick Cronin, C<< <patrick at cronin-tech.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-iugm at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=IUGM>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc IUGM::Cache


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

1; # End of IUGM::Cache
