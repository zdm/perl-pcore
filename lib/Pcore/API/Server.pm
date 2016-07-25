package Pcore::API::Server;

use Pcore -class;
use Pcore::API::Response;
use Pcore::API::Server::Hash;

has namespace       => ( is => 'ro', isa => Str,         required => 1 );
has default_version => ( is => 'ro', isa => PositiveInt, required => 1 );

has map => ( is => 'ro', isa => HashRef, init_arg => undef );
has '_hash_rpc' => ( is => 'lazy', isa => InstanceOf ['Pcore::Util::PM::RPC'], init_arg => undef );

# TODO scan API classes
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

    $self->{map} = {};

    for my $class ( sort keys $controllers->%* ) {
        P->class->load($class);

        my $path = $controllers->{$class};

        if ( !$class->does('Pcore::API::Server::Class') ) {
            delete $controllers->{$class};

            say qq["$class" is not a consumer of "Pcore::API::Server::Class"];

            next;
        }

        my $version;

        if ( $path =~ s[\A/v(\d+)][]sm ) {
            $version = $1;
        }
        else {
            say qq[Can not determine API version "$class"];

            next;
        }

        my $obj = bless { api => $self }, $class;

        my $map = $obj->map;

        $self->{map}->{$version}->{$path} = {
            class  => $class,
            method => $map,
        };
    }

    # TODO check default version

    say dump $self->{map};

    return;
}

sub _build__hash_rpc($self) {
    return P->pm->run_rpc(
        'Pcore::API::Server::Hash',
        workers   => 1,
        buildargs => {
            scrypt_N   => 16_384,
            scrypt_r   => 8,
            scrypt_p   => 1,
            scrypt_len => 32,
        },
    );
}

# TODO
sub api_call ( $self, $version, $class, $method, $data, $auth, $cb ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    $version //= $self->default_version;

    my $on_finish = sub ( $status, $reason = undef, $result = undef ) {
        my $api_res = Pcore::API::Response->new( { status => $status, defined $reason ? ( reason => $reason ) : () } );

        $api_res->{result} = $result;

        $cb->($api_res) if $cb;

        $blocking_cv->($api_res) if $blocking_cv;

        return;
    };

    my $map = $self->{map}->{$version}->{$class};

    if ( !$map ) {
        $on_finish->( 404, q[API class was not found] );
    }
    elsif ( !exists $map->{method}->{$method} ) {
        $on_finish->( 404, q[API method was not found] );
    }
    else {

        # TODO check auth
        if (0) {
            $on_finish->( 401, q[Unauthorized] );
        }
        else {
            my $obj = bless { api => $self }, $map->{class};

            $obj->$method( $data, $on_finish );
        }
    }

    return defined $blocking_cv ? $blocking_cv->recv : ();
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 45                   | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 100                  | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 34                   | ValuesAndExpressions::ProhibitNoisyQuotes - Quotes used with a noisy string                                    |
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
