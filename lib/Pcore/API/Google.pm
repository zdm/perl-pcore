package Pcore::Handle::API::Google;

use Pcore -class;
use Pcore::Util::Text qw[to_camel_case];

with qw[Pcore::Core::H::Role::Wrapper];

has '+h_disconnect_on' => ( default => undef );

has key => ( is => 'ro', isa => Str, required => 1 );

has api_url => ( is => 'lazy', isa => Str, init_arg => undef );

# H
sub h_connect {
    my $self = shift;

    return;
}

sub h_disconnect {
    my $self = shift;

    return;
}

sub _build_api_url {
    my $self = shift;

    return 'https://www.googleapis.com/';
}

sub call {
    my $self   = shift;
    my $path   = shift;
    my $params = shift;

    my ( $class_path, $method ) = split /#/sm, $path;

    $method = 'api_' . $method;

    my $class = to_camel_case( $class_path, ucfirst => 1, split => q[/], join => q[::] );

    my $obj = P->class->load( $class, ns => ref $self, does => 'Pcore::Handle::API::Google::_Role' )->new;

    my $url = $self->api_url . $obj->api_path . q[?] . $self->_prepare_params($params);

    return $obj->$method($url);
}

sub _prepare_params {
    my $self   = shift;
    my $params = shift;

    my $res = {    #
        key => $self->key,
    };

    for my $param ( keys $params->%* ) {
        if ( ref $params->{$param} eq 'ARRAY' ) {
            $res->{$param} = join q[,], $params->{$param}->@*;
        }
        else {
            $res->{$param} = $params->{$param};
        }
    }

    return P->data->to_uri($res);
}

package Pcore::Handle::API::Google::_Role;

use Pcore -role;

sub call {
    my $self = shift;
    my $ua   = shift;
    my $url  = shift;

    my $res = $ua->get($url);

    my $json = P->data->from_json( $res->content );

    return $json;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 59                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
