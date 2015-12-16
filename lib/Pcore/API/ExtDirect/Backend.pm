package Pcore::API::Backend;

use Pcore -role;
use Pcore::API::Call;

requires qw[deploy_api preload_api_map get_api_map get_api_class_js call_api do_authentication do_signout];

has is_authenticated => ( is => 'lazy', isa => Int, writer    => '_set_is_authenticated', clearer => 1, init_arg => undef );    # FALSE // uid
has token            => ( is => 'rwp',  isa => Str, predicate => 1,                       clearer => 1, init_arg => undef );    # token as hex string
has sid              => ( is => 'rwp',  isa => Str, predicate => 1,                       clearer => 1, init_arg => undef );    # sid as hex string

has _has_psgi_app => ( is => 'lazy', isa => Bool, init_arg => undef );

no Pcore;

# API
sub call {
    my $self = shift;

    my $call;

    if ( ref $_[0] eq 'Pcore::API::Call' ) {
        $call = shift;
    }
    else {
        $call = Pcore::API::Call->new(@_);
    }

    return $self->call_api($call);
}

# AUTH
sub _build__has_psgi_app {
    my $self = shift;

    if ( $self->can('app') && $self->app->does('Pcore::App::PSGI::Role') ) {
        return 1;
    }
    else {
        return 0;
    }
}

sub _build_is_authenticated {
    my $self = shift;

    # try to automatically retrive authentication credentials
    # token has priority before sid
    if ( !$self->has_token && !$self->has_sid ) {

        # try to perform auto-authentication by token or by sid
        # only if API used from PSGI app
        if ( $self->_has_psgi_app ) {
            my $res = $self->app->router->call('/api/#auto_auth')->content;

            if ( $res->{token} ) {
                $self->_set_token( $res->{token} );
            }
            elsif ( $res->{sid} ) {
                $self->_set_sid( $res->{sid} );
            }
        }
    }

    if ( $self->has_token ) {
        if ( my $res = $self->do_authentication( token => $self->token ) ) {
            return $res->{uid};
        }
    }
    elsif ( $self->has_sid ) {
        if ( my $res = $self->do_authentication( sid => $self->sid ) ) {
            return $res->{uid};
        }
    }

    $self->signout;

    return 0;
}

sub authenticate {
    my $self = shift;
    my %args = (
        token    => undef,    # token as hex string
        username => undef,
        password => undef,    # password as plain text string
        digest   => undef,    # digest as hex string
        opaque   => 0,        # mandatory for digest authentication
        @_,
    );

    if ( $args{token} ) {
        $self->end_session;

        $self->_set_token( $args{token} );
    }
    elsif ( $args{username} && $args{digest} ) {
        $self->signout;

        if ( my $res = $self->do_authentication( username => $args{username}, digest => $args{digest}, opaque => $args{opaque} ) ) {
            $self->_set_is_authenticated( $res->{uid} // 0 );
            $self->_set_sid( $res->{sid} ) if $res->{sid};
        }
    }
    elsif ( $args{username} && $args{password} ) {
        $self->signout;

        if ( my $res = $self->do_authentication( username => $args{username}, password => $args{password} ) ) {
            $self->_set_is_authenticated( $res->{uid} // 0 );
            $self->_set_sid( $res->{sid} ) if $res->{sid};
        }
    }

    return;
}

sub is_superuser {
    my $self = shift;

    return $self->is_authenticated == 1 ? 1 : 0;
}

# physically delete sid
# disallow auto-auth on next is_authenticated call
sub signout {
    my $self = shift;

    $self->clear_token;

    $self->do_signout if $self->has_sid;
    $self->clear_sid;

    $self->_set_is_authenticated(0);

    return;
}

# allow auto-auth on next is_authenticated call
sub end_session {
    my $self = shift;

    $self->clear_token;
    $self->clear_sid;
    $self->clear_is_authenticated;

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 54                   │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
