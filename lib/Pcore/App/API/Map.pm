package Pcore::App::API::Map;

use Pcore -class;

has app => ( is => 'ro', isa => ConsumerOf ['Pcore::App'], required => 1 );

has method => ( is => 'lazy', isa => HashRef, init_arg => undef );
has obj => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

sub _build_method ($self) {
    my $method = {};

    my $ns_path = ( ref( $self->app ) =~ s[::][/]smgr ) . '/API';

    my $class;

    # scan namespace, find and preload controllers
    for my $inc ( grep { !ref } @INC ) {
        if ( -d "$inc/$ns_path" ) {
            my $guard = P->file->chdir("$inc/$ns_path");

            P->file->find(
                "$inc/$ns_path",
                abs => 0,
                dir => 0,
                sub ($path) {

                    # .pm file
                    if ( $path->suffix eq 'pm' ) {

                        # API class must be located in V\d+ directory
                        return if $path !~ /\AV\d+/sm;

                        my $route = $path->dirname . $path->filename_base;

                        $class->{$route} = "$ns_path/$route" =~ s[/][::]smgr;
                    }

                    return;
                }
            );
        }
    }

    for my $class_path ( sort keys $class->%* ) {
        my $class_name = $class->{$class_path};

        P->class->load($class_name);

        die qq["$class_name" must be a consumer of "Pcore::App::API::Role"] if !$class_name->does('Pcore::App::API::Role');

        # prepare API object route
        $class_path =~ s/\AV/v/sm;

        # create API object and store in cache
        my $obj = $self->{obj}->{$class_name} = $class_name->new( { app => $self->app } );

        my $obj_map = $obj->api_map;

        # parse API version
        my ($version) = $class_path =~ /\Av(\d+)/sm;

        # validate obj API map
        for my $method_name ( sort keys $obj_map->%* ) {
            my $method_id = qq[/$class_path/$method_name];

            my $local_method_name = "api_$method_name";

            $method->{$method_id} = {
                $obj_map->{$method_name}->%*,
                id                => $method_id,
                version           => "v$version",
                class_name        => $class_name,
                class_path        => "/$class_path",
                method_name       => $method_name,
                local_method_name => $local_method_name,
            };

            # method should exists
            die qq[API method "$local_method_name" is not exists. By convention api methods should be prefixed with "api_" prefix] if !$obj->can($local_method_name);

            # validate api method configuration
            die qq[API method "$method_id" requires description] if !$method->{$method_id}->{desc};
        }
    }

    return $method;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 45, 64, 70           | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Map

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
