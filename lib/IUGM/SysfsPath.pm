package IUGM::SysfsPath;

# A Devpath is a filepath to a device record within the Sysfs tree
# E.g. /sys/devices/platform/soc/3f98000.usb/usb1/1-1/1-1.4/1-1.4:1.0/ttyUSB0/tty/ttyUSB0

use Moo;
use Types::Path::Tiny qw( Path );
use Path::Tiny qw(); # do not import "path"
use IUGM::Error;

our $VERSION = '0.01';

has path => (
    is => 'ro',
    isa => Path,
    required => 1,
);

sub BUILDARGS {
    my ($class, %args) = @_;

   if (exists $args{path} && defined $args{path}) {
        # Convert string path to Path::Tiny instance
        if (ref $args{path} eq '' && length $args{path}) {
            $args{path} = Path::Tiny->new($args{path})
        }
    }
 
    return \%args; 
}

sub attribute {
    my $self = shift;
    my $attribute = shift;

    my $attr_path = $self->path->child($attribute);    
    
    IUGM::Error->throw("Unknown attribute name $attribute in " . $self->path->stringify)
        if ! $attr_path->exists;
    
    my @lines = $attr_path->lines({'chomp' => 1, 'count' => 1});
    
    return $lines[0];
}

sub ancestor_with_attributes {
    my ($self, @attributes) = @_;
    
    my $ancestor = $self->path;
    my $root_dir = Path::Tiny->rootdir;
    do {
        return IUGM::SysfsPath->new(path => $ancestor)
            if scalar @attributes == scalar (grep {
               $ancestor->child($_)->exists
            } @attributes);
    
        $ancestor = $ancestor->parent;
    } while ($ancestor ne $root_dir);
    
    IUGM::Error->throw(
        q{Couldn't find an ancestor for }
        . $self->path
        . qq{ that contained the attribute(s): @attributes!}
    );
    
    return;
}

1;

__END__