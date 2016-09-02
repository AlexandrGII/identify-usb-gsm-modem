package IUGM::FileLock;

use Moo;
use MooX::Types::MooseLike::Base qw( :all );
use Fcntl qw( :flock );
use IUGM::Error;
use Readonly;

our $VERSION = '0.01';

Readonly my $STATUS_LOCKED_EX => 'locked_ex';
Readonly my $STATUS_LOCKED_SH => 'locked_sh';
Readonly my $STATUS_UNLOCKED => 'unlocked';

has lockfile => (
    is => 'ro',
    isa => Str,
    required => 1,
);

has _lockfile_fh => (
    is => 'rw',
    isa => FileHandle,
);

has status => (
    is => 'rwp',
    isa => Enum[$STATUS_LOCKED_EX, $STATUS_LOCKED_SH, $STATUS_UNLOCKED],
    default => $STATUS_UNLOCKED,
);

sub lock_ex {
    my $self = shift;
    my $non_blocking = shift;

    $self->_open_lockfile('>>');
    if ($self->_acquire_lock(
        LOCK_EX | (defined $non_blocking && $non_blocking ? LOCK_NB : 0)
    )) {
        $self->_set_status($STATUS_LOCKED_EX);
    }
    
    return $self;
}

sub lock_sh {
    my $self = shift;
    my $non_blocking = shift;
    
    $self->_open_lockfile('<');
    if ($self->_acquire_lock(
        LOCK_SH | (defined $non_blocking && $non_blocking ? LOCK_NB : 0)
    )) {
        $self->_set_status($STATUS_LOCKED_SH);
    }
    
    return $self;
}

sub unlock {
    my $self = shift;

    flock ($self->_lockfile_fh, LOCK_UN)
        or IUGM::Error->throw(
            q{Couldn't unlock the } . $self->lockfile . q{ lockfile!}
        );
    close ($self->_lockfile_fh);
    
    $self->_set_status($STATUS_UNLOCKED);

    return $self;
}

sub is_locked_ex {
    return shift->status eq $STATUS_LOCKED_EX;
}

sub is_locked_sh {
    return shift->status eq $STATUS_LOCKED_SH;
}

sub is_locked {
    return ! shift->is_unlocked;
}

sub is_unlocked {
    return shift->status eq $STATUS_UNLOCKED;
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
    
    my $lock_succeeded = flock ($self->_lockfile_fh, $operation);
    IUGM::Error->throw(
        q{Couldn't acquire a lock on }
        . $self->lockfile
        . qq{ with mode $operation!}
    ) unless $lock_succeeded || !($operation & LOCK_NB);
    
    return $lock_succeeded;
}

1;