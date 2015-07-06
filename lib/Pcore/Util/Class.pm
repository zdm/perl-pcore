package Pcore::Util::Class;

use Pcore;
use Sub::Util qw[];    ## no critic qw(Modules::ProhibitEvilModules)

sub load {
    my $self  = shift;
    my $class = shift;
    my %args  = (
        ns   => undef,
        isa  => undef,    # InstanceOf
        does => undef,    # ConsumerOf
        @_,
    );

    my $class_filename;
    if ( $class =~ /[.]pm\z/sm ) {
        $class_filename = $class;
    }
    else {
        $class = $self->resolve_class_name( $class, $args{ns} );
        $class_filename = ( $class =~ s[::][/]smgr ) . q[.pm];
    }

    require $class_filename;

    die qq[Error loading class "$class". Class must be instance of "$args{isa}"]  if $args{isa}  && !$class->isa( $args{isa} );
    die qq[Error loading class "$class". Class must be consumer of "$args{does}"] if $args{does} && !$class->does( $args{does} );

    return $class;
}

sub resolve_class_name {
    my $self  = shift;
    my $class = shift;
    my $ns    = shift;

    if ( $class =~ s/\A[+]//sm ) {
        return $class;
    }
    else {
        return $ns ? qq[${ns}::${class}] : $class;
    }
}

sub set_sub_prototype {
    my $self = shift;

    return Sub::Util::set_prototype(@_);
}

sub get_sub_prototype {
    my $self = shift;

    return Sub::Util::prototype(@_);
}

# allow to specify name as '::<name>', caller namespace will be used as full sub name
sub set_subname {
    my $self = shift;

    return Sub::Util::set_subname(@_);
}

sub get_sub_name {
    my $self = shift;

    my ( $package, $name ) = Sub::Util::subname( $_[0] ) =~ /^(.+)::(.+)$/sm;

    return $name;
}

sub get_sub_fullname {
    my $self = shift;

    my $full_name = Sub::Util::subname( $_[0] );

    if (wantarray) {
        my ( $package, $name ) = $full_name =~ /^(.+)::(.+)$/sm;

        return $name, $package;
    }
    else {
        return $full_name;
    }
}

1;
__END__
=pod

=encoding utf8

=cut
