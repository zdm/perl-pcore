package Pcore::API::Backend::Remote;

use Pcore -class;
use Pcore::Util::List qw[pairs];

with qw[Pcore::API::Backend];

has addr => ( is => 'ro', isa => Str, required => 1 );

has session_cookie_name => ( is => 'lazy', isa => Str, default => 'sid' );
has _ua => ( is => 'lazy', isa => InstanceOf ['Pcore::HTTP::Request'], init_arg => undef );

sub _build__ua ($self) {
    my $ua = P->http->request;

    # if ( $self->has_ca ) {
    #     $ua->ssl_opts( verify_hostname => 1 );
    #     $ua->ssl_opts( SSL_ca_file     => $self->ca );
    # }

    # $ua->default_header( 'Accept-Encoding' => scalar HTTP::Message::decodable() );
    # $ua->default_header( 'Content-Type'    => 'application/json' );
    # $ua->default_header( 'Accept'          => 'application/json' );

    return $ua;
}

sub _get_url {
    my $self = shift;

    return $self->addr . q[/api/];
}

sub _get_auth_headers {
    my $self = shift;

    my %headers;

    if ( $self->has_token ) {
        $headers{AUTHORIZATION} = 'Token ' . $self->token;
    }
    elsif ( $self->has_sid ) {
        $headers{COOKIE} = $self->session_cookie_name . q[=] . $self->sid;
    }

    return %headers;
}

# API
sub deploy_api {    # this is loopback, remote backend can't deploy API
    my $self = shift;

    return;
}

sub preload_api_map {    # this is loopback, remote backend hasn't API map
    my $self = shift;

    return;
}

sub get_api_map {
    my $self = shift;

    my $url = $self->_get_url;

    my $res = $self->_ua->get( $url . 'map/', $self->_get_auth_headers );

    my $api_map = {};

    if ( $res->is_success ) {
        $api_map = P->data->from_json( $res->content->$* );
    }

    return $api_map;
}

sub get_api_class_js {
    my $self = shift;
    my %args = (
        path  => undef,
        class => undef,
        @_,
    );

    my $url = $self->_get_url . $args{path} . q[/] . $args{class} . q[.js];

    my $res = $self->_ua->get( $url, $self->_get_auth_headers );

    my $js = q[];

    if ( $res->is_success ) {
        $js = $res->content;
    }

    return $js;
}

sub call_api {
    my $self = shift;
    my $call = shift;

    my $req = [ extActions => { content => P->data->to_json($call), content_type => 'application/json' }, ];

    # attach uploads to request array
    if ( $call->has_uploads ) {
        for my $action ( grep { $_->uploads } $call->actions->@* ) {

            # add upload TID header
            for my $pair ( pairs( $action->uploads->@* ) ) {
                $pair->value->replace_headers( TID => $action->tid );

                push $req, $pair->key, $pair->value;
            }
        }
    }

    my $res = $self->_ua->post( $self->_get_url . 'rpc/', $req, $self->_get_auth_headers );

    my $res_call;

    # parse result
    if ( $res->is_success ) {
        my $content = $res->content;

        $content->$* =~ s[\A<textarea>|</textarea>\z][]smg;

        $res_call = Pcore::API::Call->new( P->data->from_json( $content->$* ) );
    }
    else {
        $res_call = Pcore::API::Call->new;

        for my $action ( $call->actions->@* ) {
            $res_call->add_action( $action->exception( $res->status_message ) );
        }
    }

    return $res_call;
}

# AUTH
sub do_authentication {
    my $self = shift;
    my %args = (
        token    => undef,    # token as hex string
        sid      => undef,    # "sid" cookie value, encrypted
        username => undef,
        password => undef,    # password as plain text string
        digest   => undef,    # digest as hex string
        opaque   => 0,        # mandatory for digest authentication
        @_,
    );

    my $url = $self->_get_url . q[auth/];
    my $res;
    my $auth = {
        uid => undef,
        sid => undef,
    };

    if ( $args{token} ) {
        $res = $self->_ua->post( $url, q[], AUTHORIZATION => 'Token ' . $args{token} );
    }
    elsif ( $args{sid} ) {
        $res = $self->_ua->post( $url, q[], COOKIE => $self->session_cookie_name . q[=] . $args{sid} );
    }
    elsif ( $args{digest} ) {
        $res = $self->_ua->get( $self->_get_url . q[signin/], AUTHORIZATION => qq[Digest username="$args{username}", response="$args{digest}", opaque="$args{opaque}", qop="", algorithm="MD5", realm=""] );

        # get sid from cookie value
        if ( $res->is_success ) {
            $auth->{sid} = $res->cookies->{ $self->session_cookie_name }->value if $res->cookies->{ $self->session_cookie_name };
        }
    }
    else {
        my $auth_req = $self->_ua->get( $self->_get_url . q[signin/] );
        if ( $auth_req->status == 401 ) {
            my $HA1    = P->digest->md5_hex(qq[$args{username}::$args{password}]);
            my $HA2    = P->digest->md5_hex('GET:/api/signin/');
            my $digest = P->digest->md5_hex(qq[$HA1:nonce:$HA2]);

            my ($opaque) = $auth_req->headers->{WWW_AUTHENTICATE} =~ /opaque="(.+?)"/sm;

            $res = $self->_ua->get( $self->_get_url . q[signin/], AUTHORIZATION => qq[Digest username="$args{username}", response="$digest", opaque="$opaque", qop="", algorithm="MD5", realm=""] );

            # get sid from cookie value
            if ( $res->is_success ) {
                $auth->{sid} = $res->cookies->{ $self->session_cookie_name }->[0]->value if $res->cookies->{ $self->session_cookie_name };
            }
        }
        else {
            $res = $auth_req;
        }
    }

    if ( $res->is_success ) {
        my $json = P->data->from_json( $res->content->$* );

        $auth->{uid} = $json->{uid} if $json->{uid};
    }

    return $auth;
}

sub do_signout {
    my $self = shift;

    return unless $self->has_sid;

    $self->_ua->get( $self->_get_url . q[signout/], $self->_get_auth_headers );

    return;
}

1;
__END__
=pod

=encoding utf8

=cut
