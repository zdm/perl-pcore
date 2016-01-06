package Pcore::API::Backend::Local;

use Pcore -role;
use Pcore::Util::Text qw[to_camel_case to_snake_case];

with qw[Pcore::API::Backend];

requires qw[run_ddl sync_api_map _build_api_map auth_method find_user create_sid cleanup_expired_sessions];

has app => ( is => 'ro', isa => ConsumerOf ['Pcore::App::Role'], required => 1, weak_ref => 1 );
has h_name => ( is => 'ro', isa => Str, required => 1 );    # API handle name, should be in h cache

has session_ttl              => ( is => 'ro',  isa => PositiveInt, default => 60 * 30 );       # session ttl in seconds, can't be 0
has sessions_cleanup_timeout => ( is => 'ro',  isa => Int,         default => 60 * 10 );       # cleanup expired session every N seconds
has sessions_last_cleaned    => ( is => 'rwp', isa => Int,         default => sub {time} );    # when sessions was expired last time

has sid_bytes       => ( is => 'ro', isa => Int, default => 32 );                              # bytes, default sid length
has token_bytes     => ( is => 'ro', isa => Int, default => 32 );                              # bytes, default token length
has password_length => ( is => 'ro', isa => Int, default => 16 );                              # chars, default password length
has bcrypt_cost     => ( is => 'ro', isa => Int, default => 10 );                              # 1..31, default bcrypt cost

has api_map => ( is => 'lazy', isa => HashRef, clearer => 1, init_arg => undef );

has h_cache => ( is => 'lazy', isa => InstanceOf ['Pcore::Core::H::Cache'], init_arg => undef, weak_ref => 1 );    # handles cache object

has _api_obj_cache => ( is => 'lazy', isa => HashRef, default => sub { {} }, clearer => 1, init_arg => undef );

around auth_method => sub {
    my $orig       = shift;
    my $self       = shift;
    my $method_cfg = shift;

    return 1 if $method_cfg->{public};                                                                             # authentication / authorization isn't required

    return 1 if $self->is_superuser;                                                                               # authorizaton isn't required for superuser

    return if !$self->is_authenticated;                                                                            # not authenticated

    return $self->$orig( $method_cfg->{id} );                                                                      # perform real authorization check
};

# deploy API
sub deploy_api {
    my $self = shift;

    $self->run_ddl;

    state $init = !!require Pcore::API::Map::Scanner;

    my $scanner = Pcore::API::Map::Scanner->new(
        {   backend => $self,
            h_cache => $self->h_cache,
            app_ns  => $self->app->ns,
        }
    );

    my $api_map = $scanner->scan;

    $self->sync_api_map( $api_map, app => 'test' );

    $self->clear_api_map;

    # build api classes
    for my $action ( keys $self->api_map->%* ) {
        my $obj = $self->get_api_obj($action);

        warn qq[    Call APP_BUILD for: "] . $self->api_map->{$action}->{class} . q["];

        $obj->APP_BUILD if !$obj->__app_builded;
    }

    return;
}

around _build_api_map => sub {
    my $orig = shift;
    my $self = shift;

    $self->_clear_api_obj_cache;

    return $self->$orig(@_);
};

# ACCESSORS
sub _build_h_cache {
    my $self = shift;

    return $self->app->h;
}

# API METHODS
sub preload_api_map {
    my $self = shift;

    $self->api_map;

    return;
}

sub get_api_map {
    my $self = shift;

    my $api_map = {    #
        url => q[/api/rpc/],
    };

    for my $action ( sort keys $self->api_map->%* ) {
        $api_map->{actions}->{$action} = [];

        for my $method ( sort keys $self->api_map->{$action}->{methods}->%* ) {
            my $method_cfg = $self->api_map->{$action}->{methods}->{$method};

            next unless $self->auth_method($method_cfg);

            push $api_map->{actions}->{$action}->@*, $method_cfg;
        }
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

    my $perl_class = to_camel_case( $args{path}, ucfirst => 1, split => q[/], join => q[::] );

    if ( my $obj = $self->get_api_obj( undef, $perl_class ) ) {
        $obj->_set_ext_class_name( $args{class} );

        my $res = $obj->ext_generate_class( readable => $self->app->env_is_devel );

        return $res;
    }

    return;
}

sub call_api {
    my $self = shift;
    my $call = shift;

    my $res_call = Pcore::API::Call->new;

    for my $action ( $call->actions->@* ) {

        # find action
        if ( !exists $self->api_map->{ $action->_real_action } ) {
            $res_call->add_action( $action->exception('Unknown action') );
            next;
        }

        my $action_cfg = $self->api_map->{ $action->_real_action };

        # find method
        if ( !exists $action_cfg->{methods}->{ $action->method } ) {
            $res_call->add_action( $action->exception('Unknown method') );
            next;
        }

        my $method_cfg = $action_cfg->{methods}->{ $action->method };

        # authorize method
        if ( !$self->auth_method($method_cfg) ) {
            $res_call->add_action( $action->exception('Method authorization error') );
            next;
        }

        my $obj = $self->get_api_obj( $action->_real_action );

        # api class wasn't found
        if ( !$obj ) {
            $res_call->add_action( $action->exception(q[Internal error, action isn't implemented]) );
            next;
        }

        my $response = $obj->_api_map->call_method($action);

        $res_call->add_action($response);
    }

    return $res_call;
}

sub get_api_obj {
    my $self   = shift;
    my $action = shift;
    my $class  = shift;

    if ( !$class ) {
        $action =~ s[/][.]smg;

        return if !exists $self->api_map->{$action};

        $class = $self->api_map->{$action}->{class};
    }
    else {
        $action = to_snake_case( $class, split => q[::], join => q[.] );
    }

    if ( !exists $self->_api_obj_cache->{$class} ) {

        # try to create object
        try {
            my $obj = P->class->load( $class, ns => $self->app->ns . '::API' )->new(
                {   backend        => $self,
                    h_cache        => $self->h_cache,
                    app_name       => $self->app->name,
                    ext_app_name   => 'api',
                    ext_class_ns   => $action,
                    ext_class_name => q[],
                }
            );

            # store object into cache, if was created successfully
            $self->_api_obj_cache->{$class} = $obj;
        }
        catch {
            my $e = shift;

            $e->sendlog;

            return;
        };
    }

    return $self->_api_obj_cache->{$class};
}

# H
# this method return API handle
sub h_api {
    my $self = shift;

    my $h_name = $self->h_name;

    return $self->h_cache->$h_name;
}

# AUTH
sub do_authentication {
    my $self = shift;
    my %args = (
        token    => undef,    # token as hex string
        sid      => undef,    # sid as hex string
        username => undef,
        password => undef,    # password as plain text string
        digest   => undef,    # digest as hex string
        @_,
    );

    # cleanup expired sessions
    if ( !$self->sessions_last_cleaned || $self->sessions_last_cleaned < time - $self->sessions_cleanup_timeout ) {
        $self->_set_sessions_last_cleaned(time);
        $self->cleanup_expired_sessions;
    }

    if ( $args{token} ) {     # auth by token
        if ( my $user = $self->find_user( token => $args{token} ) ) {
            return $user;
        }
    }
    elsif ( $args{sid} ) {    # auth by sid
        if ( my $user = $self->find_user( sid => $args{sid} ) ) {
            return $user;
        }
    }
    elsif ( $args{username} && $args{digest} ) {    # auth by digest
        if ( my $user = $self->find_user( username => $args{username} ) ) {
            if ( $user->{digest} eq $self->_hash_digest( $args{username}, $args{digest} ) ) {
                return {
                    uid => $user->{uid},
                    sid => $self->create_sid( $user->{uid} ),
                };
            }
        }
    }
    elsif ( $args{username} && $args{password} ) {    # auth by password
        if ( my $user = $self->find_user( username => $args{username} ) ) {
            if ( $user->{digest} eq $self->hash_password( $args{username}, $args{password} ) ) {
                return {
                    uid => $user->{uid},
                    sid => $self->create_sid( $user->{uid} ),
                };
            }
        }
    }

    return;
}

sub generate_sid {    # return sid as hex string
    my $self = shift;

    return P->random->bytes_hex( $self->sid_bytes );
}

sub generate_token {    # return token as hex string
    my $self = shift;

    return P->random->bytes_hex( $self->token_bytes );
}

sub generate_password {    # return newly generated plain text password
    my $self = shift;

    return P->random->password( $self->password_length );
}

sub hash_password {        # return salted digest hash as binary string
    my $self     = shift;
    my $username = shift;
    my $password = shift;    # plain password string

    # create digest
    my $HA1    = P->digest->md5_hex( $username . '::' . $password );    # realm is ""
    my $HA2    = P->digest->md5_hex('GET:/api/signin/');
    my $digest = P->digest->md5_hex( $HA1 . ':nonce:' . $HA2 );         # nonce is hardcoded as "nonce"

    return $self->_hash_digest( $username, $digest );
}

sub _hash_digest {                                                      # return salted digest hash as binary string
    my $self     = shift;
    my $username = shift;
    my $digest   = shift;                                               # digest as hex string

    my $salt = P->digest->md5($username);

    return P->digest->bcrypt( $digest, $salt, $self->bcrypt_cost );
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 64, 107, 110         │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 67                   │ ValuesAndExpressions::ProhibitInterpolationOfLiterals - Useless interpolation of literal string                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 320                  │ ValuesAndExpressions::ProhibitNoisyQuotes - Quotes used with a noisy string                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
