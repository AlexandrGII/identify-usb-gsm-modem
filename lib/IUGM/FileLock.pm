package IUGM::FileLock;

use Moo;
use MooX::Types::MooseLike::Base qw( :all );
use Fcntl qw( :flock );

has lockfile => (
    is => 'ro',
    isa => Str,
    required => 1,
);

has _lockfile_fh => (
    is => 'rw',
    isa => FileHandle,
);

sub lock_ex {
    my $self = shift;
    my $non_blocking = shift;
    
    $self->_open_lockfile('>>');
    $self->_acquire_lock(
        LOCK_EX | (defined $non_blocking && $non_blocking ? LOCK_NB : 0)
    )
    
    return $self;
}

sub lock_sh {
    my $self = shift;
    my $non_blocking = shift;
    
    $self->_open_lockfile('<');
    $self->_acquire_lock(
        LOCK_SH | (defined $non_blocking && $non_blocking ? LOCK_NB : 0)
    );
    
    return $self;
}

sub unlock {
    my $self = shift;

    flock ($self->_lockfile_fh, LOCK_UN)
        or IUGM::Error->throw(
            q{Couldn't unlock the } . $self->_lockfile . q{ lockfile!};
        );
    close ($self->_lockfile_fh);

    return $self;
}

sub _open_lockfile {
    my $self = shift;
    my $mode = shift;
    
    open (my $lock, $mode, $self->lockfile)
        or IUGM::Error->throw(
            q{Couldn't open the lockfile at } . $self->lockfile
        );
    $self->_lockfile_fh($lock);
    
    return $self;
}

sub _acquire_lock {
    my $self = shift;
    my $operation = shift;
    
    flock ($lock, $operation)
        or IUGM::Error->throw(
            q{Coudln't acquire a lock on }
            . $self->_lockfile
            . qq{ with mode $operation!}
        );
    
    return $self;
}

1;