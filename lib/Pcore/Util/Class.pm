package Pcore::Util::Class;

use Pcore;
use Sub::Util qw[];    ## no critic qw[Modules::ProhibitEvilModules]

sub load ( $module, @ ) {
    my %args = (
        ns  => undef,
        isa => undef,
        splice @_, 1,
    );

    my $package = module_to_package($module);

    $package = resolve_class_name( $package, $args{ns} );

    $module = package_to_module($package);

    require $module;

    die qq[Error loading module "$module". Module must be instance of "$args{isa}"] if $args{isa} && !$package->isa( $args{isa} );

    return $package;
}

sub find ( $module, @ ) {
    my %args = (
        ns => undef,
        splice @_, 1,
    );

    my $package = module_to_package($module);

    $package = resolve_class_name( $package, $args{ns} );

    $module = package_to_module($package);

    my $found;

    # find class in @INC
    for my $inc ( grep { !is_ref $_ } @INC ) {
        if ( -f "$inc/$module" ) {
            $found = "$inc/$module";

            last;
        }
    }

    return $found;
}

sub find1 ( $class, @ ) {
    my %args = (
        ns => undef,
        splice @_, 1,
    );

    my $class_filename;

    if ( $class =~ /[.]pm\z/sm ) {
        $class_filename = $class;
    }
    else {
        $class = resolve_class_name( $class, $args{ns} );

        $class_filename = ( $class =~ s[::][/]smgr ) . q[.pm];
    }

    my $found;

    # find class in @INC
    for my $inc ( grep { !ref } @INC ) {
        if ( -f "$inc/$class_filename" ) {
            $found = "$inc/$class_filename";

            last;
        }
    }

    return $found;
}

sub resolve_class_name ( $class, $ns = undef ) {
    if ( substr( $class, 0, 1 ) eq '+' ) {
        return $class;
    }
    else {
        return $ns ? "${ns}::$class" : $class;
    }
}

sub module_to_package ($module) {
    if ( substr( $module, -3 ) eq '.pm' ) {
        $module =~ s[/][::]smg;

        substr $module, -3, 3, $EMPTY;
    }

    return $module;
}

sub package_to_module ($package) {
    if ( substr( $package, -3 ) ne '.pm' ) {
        $package =~ s[::][/]smg;

        $package .= '.pm';
    }

    return $package;
}

sub set_sub_prototype {
    return &Sub::Util::set_prototype;    ## no critic qw[Subroutines::ProhibitAmpersandSigils]
}

sub get_sub_prototype {
    return &Sub::Util::prototype;        ## no critic qw[Subroutines::ProhibitAmpersandSigils]
}

# allow to specify name as '::<name>', caller namespace will be used as full sub name
sub set_subname {
    return &Sub::Util::set_subname;      ## no critic qw[Subroutines::ProhibitAmpersandSigils]
}

sub get_sub_name {
    my ( $package, $name ) = &Sub::Util::subname =~ /^(.+)::(.+)$/sm;    ## no critic qw[Subroutines::ProhibitAmpersandSigils]

    return $name;
}

sub get_sub_fullname {
    my $full_name = &Sub::Util::subname;                                 ## no critic qw[Subroutines::ProhibitAmpersandSigils]

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
