package IUGM::PriorityLogger;

use Moo;
with 'MooX::Singleton';
use MooX::Types::MooseLike::Base qw( :all );
use English qw( -no_match_vars );
use IO::Interactive qw( is_interactive );
use IUGM::Error;
use autodie;
use Readonly;

our $VERSION = '0.01';

Readonly my $PRIORITY_EVENT => 1;
Readonly my $PRIORITY_INFO => 2;
Readonly my $PRIORITY_DEBUG => 3;

has logfile => (
    is       => 'ro',
    isa      => Str,
);
has _logfile_fh => ( is => 'ro', isa => FileHandle, lazy => 1, builder => 1 );

sub BUILDARGS {
    my ($class, %args) = @_;
    
    if (! is_interactive() && ! exists $args{logfile}) {
        IUGM::Error->throw("logfile is required when run as a daemon!");
    }
    
    return \%args;
}

# Prepare the logfile for writing
sub _build__logfile_fh {
    my $self = shift;

    if ( -e $self->logfile ) {
        if ( !-f $self->logfile || !-w $self->logfile ) {
            IUGM::Error->throw(
'If logfile path exists, it must be a file writable by you, so you can overwrite it.'
            );
        }
    }

    open my $fh, '>:encoding(utf8)', $self->logfile;

    return $fh;
}

# Write some text to the logfile
sub _log {
    my $self = shift;
    my $event_priority = shift;
    my $text = shift
      or return;

    if (is_interactive()) {
        print $text, "\n";
    }
    else {
        ## no critic (RequireCheckedSyscalls)
        print { $self->_logfile_fh } $text, "\n";
        ## use critic
    }

    return $self;
}

sub log_event {
    return shift->_log($PRIORITY_EVENT, @_);
}

sub log_info {
    return shift->_log($PRIORITY_INFO, @_);
}

sub log_debug {
    return shift->_log($PRIORITY_DEBUG, @_);
}


1;