package IUGM::DeviceCache;

use IUGM qw( $CONFIG_CACHE_FILEPATH $CONFIG_CACHE_LOCK_FILEPATH );

use Moo;
use MooX::Types::MooseLike::Base qw( :all );
use IUGM::Config;
use IUGM::FileLock;
use Readonly;
use DBI;

our $VERSION = '0.01';

Readonly my $CACHE_TABLE_NAME => 'imei';

has _dbh => (
    is => 'ro',
    isa => InstanceOf[ 'DBI::db' ],
    builder => 1,
    lazy => 1,
);

has _config => (
    is => 'ro',
    isa => InstanceOf[ 'IUGM::Config' ],
    builder => 1,
    lazy => 1,  
);

has _cache_lock_filepath => (
    is => 'ro',
    isa => Str,
    builder => 1,
    lazy => 1,
);

has _cache_filepath => (
    is => 'ro',
    isa => Str,
    builder => 1,
    lazy => 1,
);

has _cache_filelock => (
    is => 'ro',
    isa => InstanceOf[ 'IUGM::FileLock' ],
    builder => 1,
    lazy => 1,
);

sub _build__dbh {
    my $self = shift;

    my $was_locked = $self->_cache_filelock->is_locked;
    $self->_cache_filelock->lock_ex
        if ! $was_locked;

    # Connect
    my $dbh = DBI->connect(
        q{dbi:SQLite:dbname=} . $self->_cache_filepath,
        undef,
        undef,
        {
            'AutoCommit' => 1,
            'RaiseError' => 1,
            'sqlite_see_if_its_a_number' => 1,
        }
    );
    
    $self->_cache_filelock->unlock
        if ! $was_locked;

    return $dbh;
}

sub _build__cache_filelock {
    my $self = shift;
    
    return IUGM::FileLock->new(
        lockfile => $self->_cache_lock_filepath
    );
}

sub _build__config {
    return IUGM::Config->instance;
}

sub _build__cache_lock_filepath {
    my $self = shift;
    
    return $self->_config->val($CONFIG_CACHE_LOCK_FILEPATH);
}

sub _build__cache_filepath {
    my $self = shift;
    
    return $self->_config->val($CONFIG_CACHE_FILEPATH);
}

sub DEMOLISH {
    my $self = shift;
    
    if ($self->_dbh) {
        $self->_dbh->disconnect;
    }
}

# Returns undef if a value wasn't found, or, the value found was null
sub retrieve {
    my $self = shift;
    my $device_devpath = shift;
    my $device_inserted = shift;

    # Sanity check
    return if ! -e $self->_cache_filepath;

    # Enter critical region if we weren't there already
    my $was_locked = $self->_cache_filelock->is_locked;
    $self->_cache_filelock->lock_ex
        if ! $was_locked;
    
    my $cache_value = undef;
    if ($self->_imei_table_exists) {
        # Expire any entries
        my $sth = $self->_dbh->prepare(qq{
            DELETE
            FROM $CACHE_TABLE_NAME
            WHERE device_devpath = ? AND device_inserted != ?
        });
        $sth->execute($device_devpath, $device_inserted);
    
        # Read from the table
        $sth = $self->_dbh->prepare(qq{
            SELECT imei
            FROM $CACHE_TABLE_NAME
            WHERE device_devpath = ? AND device_inserted = ?
        });
        $sth->execute($device_devpath, $device_inserted);
        
        if (my @row = $sth->fetchrow_array) {
            $cache_value = $row[0];
        }
    }
        
    # Exit critical region if we weren't there already
    $self->_cache_filelock->unlock
        if ! $was_locked;
    
    return $cache_value;
}

sub store {
    my $self = shift;
    my $device_devpath = shift;
    my $device_inserted = shift;
    my $imei = shift;
    
    # Enter critical region if we weren't there already
    my $was_locked = $self->_cache_filelock->is_locked;
    $self->_cache_filelock->lock_ex
        if ! $was_locked;

    # Create the table if necessary
    if (! $self->_imei_table_exists) {
        $self->_create_imei_table;
    }

    # Store our value
    my $sth = $self->_dbh->prepare(qq{
        INSERT INTO $CACHE_TABLE_NAME
        (device_devpath, device_inserted, imei)
        VALUES (?, ?, ?)
    });
    $sth->execute($device_devpath, $device_inserted, $imei);
    
    # Exit critical region if we weren't there already
    $self->_cache_filelock->unlock
        if ! $was_locked;
}

sub _imei_table_exists {
    my $self = shift;

    my $sth = $self->_dbh->prepare(q{
        SELECT 1 FROM sqlite_master WHERE type='table' AND name LIKE ?;
    });
    $sth->execute($CACHE_TABLE_NAME);
    return 1 if $sth->fetchrow_array;
    
    return 0;
}

sub _create_imei_table {
    my $self = shift;
    
    $self->_dbh->prepare(qq{
        CREATE TABLE IF NOT EXISTS $CACHE_TABLE_NAME (
            device_devpath VARCHAR(255) NOT NULL,
            device_inserted INT(11) NOT NULL,
            imei INT(15) NOT NULL,
            PRIMARY KEY (device_devpath, device_inserted)
        )
    })->execute;
    
    return $self;
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
