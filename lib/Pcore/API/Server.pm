package Pcore::API::Server;

use Pcore -class;
use Pcore::API::Response;

has namespace => ( is => 'ro', isa => Str, required => 1 );

has map => ( is => 'ro', isa => HashRef, init_arg => undef );

sub BUILD ( $self, $args ) {
    my $ns_path = $self->namespace =~ s[::][/]smgr;

    my $controllers = {};

    # scan namespace, find and preload controllers
    for my $path ( grep { !ref } @INC ) {
        if ( -d "$path/$ns_path" ) {
            my $guard = P->file->chdir("$path/$ns_path");

            P->file->find(
                "$path/$ns_path",
                abs => 0,
                dir => 0,
                sub ($path) {
                    if ( $path->suffix eq 'pm' ) {
                        my $route = $path->dirname . $path->filename_base;

                        my $class = "$ns_path/$route" =~ s[/][::]smgr;

                        $controllers->{$class} = '/' . P->text->to_snake_case( $route, delim => '-', split => '/', join => '/' ) . '/';
                    }

                    return;
                }
            );
        }
    }

    for my $class ( sort keys $controllers->%* ) {
        P->class->load($class);

        if ( !$class->does('Pcore::API::Server::Class') ) {
            delete $controllers->{$class};

            say qq["$class" is not a consumer of "Pcore::API::Server::Class"];
        }
    }

    $self->{map} = { reverse $controllers->%* };

    say dump $self->{map};

    return;
}

sub api_call ( $self, $class, $method, $data, $auth = undef ) {
    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 39, 49               | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 30                   | ValuesAndExpressions::ProhibitNoisyQuotes - Quotes used with a noisy string                                    |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Server

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
