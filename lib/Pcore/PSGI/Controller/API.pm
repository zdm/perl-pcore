package Pcore::PSGI::Controller::API;

use Pcore qw[-role];
use Pcore::API::Call;

with qw[Pcore::PSGI::Controller];

has session_cookie_name => ( is => 'lazy', isa => Str,  default => 'sid' );
has bind_session_to_ip  => ( is => 'lazy', isa => Bool, default => 1 );

has ext_title  => ( is => 'lazy', isa => Str );
has ext_theme  => ( is => 'lazy', isa => Enum [qw[classic classic-sandbox crisp crisp-touch gray neptune neptune-touch aria]] );
has ext_locale => ( is => 'lazy', isa => Str );

our $DEFAULT_API = {
    type                 => 'remoting',
    namespace            => undef,
    disableNestedActions => $FALSE,
    maxRetries           => 0,
    timeout              => 5000,         # timeout to use for each request (milliseconds)
    enableBuffer         => 10            # buffer waiting time in millisecs
};

# allowed requests
# GET /api/map/ - return API map for currently signed user
# GET /api/signout/ - delete current SID
# GET /api/signin/?continue=<location> - digest authentication
# GET /api/<path-to-namespace>/Class.js - generate ExtJS class, typically is ExtJS model
# POST /api/ - perform API call
# POST /api/signin/ - authenticate user with passed credentials
sub run {
    my $self = shift;

    if ( $self->path ) {
        if ( $self->path eq 'signin/' ) {
            if ( $self->req->is_get ) {    # digest authentication
                return $self->_auth_digest;
            }
            elsif ( $self->req->is_post ) {    # password authentication
                return $self->_auth_password;
            }
            else {
                return $self->res->set_status(405);    # 405 - method Not Allowed
            }
        }
        elsif ( $self->path eq 'signout/' ) {
            return $self->_auth_signout;               # perform signout
        }
        elsif ( $self->path eq 'rpc/' ) {
            if ( $self->req->is_post ) {               # execute API call
                return $self->_api_call;
            }
            else {
                return $self->res->set_status(405);    # 405 - method Not Allowed
            }
        }
        elsif ( $self->path eq 'map/' ) {
            if ( $self->req->is_get ) {
                return $self->_api_map;
            }
            else {
                return $self->res->set_status(405);    # 405 - Method Not Allowed
            }
        }
        elsif ( $self->path->dirname eq q[] && $self->path->filename eq 'map.html' ) {
            return $self->_api_map_html;
        }
        elsif ( $self->path->suffix eq 'js' ) {
            return $self->_api_class_js;
        }
        else {
            return $self->res->set_status(404);
        }
    }
    else {
        if ( $self->req->is_get ) {    # ext api app entry point
            if ( !$self->path || $self->path eq 'index.html' ) {
                return $self->_api_app;
            }
            elsif ( $self->path->suffix eq 'js' ) {
                return $self->_api_class_js;
            }
            else {
                return $self->res->set_status(404);
            }
        }
        else {
            return $self->res->set_status(405);    # 405 - Method Not Allowed
        }
    }
}

sub _build_ext_title {
    my $self = shift;

    return $self->app->name . ' api';
}

sub _build_ext_theme {
    my $self = shift;

    return 'crisp';
}

sub _build_ext_locale {
    my $self = shift;

    return 'en';
}

sub _auth_digest {
    my $self = shift;

    # store continue param in cookie and redirect
    if ( keys %{ $self->req->params_get } ) {
        my $res = $self->res->set_status(307)->add_headers( LOCATION => $self->path->to_abs )->remove_cookies( $self->session_cookie_name );

        if ( $self->req->params_get->{continue} ) {
            $res->add_cookies( digest_continue => $self->req->params_get->{continue} );
        }
        else {
            $res->remove_cookies('digest_continue');
        }

        return $res;
    }

    if ( $self->req->auth_challenge_is('DIGEST') ) {
        my $opaque = try {
            return unless $self->req->auth->{opaque};
            return P->data->decode( $self->req->auth->{opaque}, portable => 1, encrypt => 1, secret => $self->app->cfg->{SECRET} );
        };

        if ( $opaque && $opaque + 30 > time ) {    # 30 secs to fill authorization form
            if ( $self->req->auth->{username} && $self->req->auth->{response} ) {
                $self->api->authenticate( username => $self->req->auth->{username}, digest => $self->req->auth->{response}, opaque => $self->req->auth->{opaque} );

                # authenticated successfully
                if ( my $uid = $self->api->is_authenticated ) {
                    my $res = $self->res->add_cookies( $self->session_cookie_name => { value => $self->api->sid, encrypt_ip => $self->bind_session_to_ip } )->set_no_cache->remove_cookies('digest_continue');

                    if ( $self->req->cookies->{digest_continue} ) {
                        $res->set_status(307)->add_headers( LOCATION => $self->req->cookies->{digest_continue} );
                    }
                    else {
                        $res->set_content( { uid => $uid } );
                    }

                    return $res;
                }
            }
        }
    }

    my $opaque = P->data->encode( time, portable => 1, encrypt => 1, secret => $self->app->cfg->{SECRET} )->$*;    # returned unchanged by client

    return $self->res->set_status(401)->add_headers( WWW_AUTHENTICATE => qq[Digest realm="", qop="", nonce="nonce", opaque="$opaque", algorithm="MD5", stale="FALSE"] )->remove_cookies( $self->session_cookie_name )->set_no_cache;
}

sub _auth_password {
    my $self = shift;

    if ( $self->req->params_post->{username} && $self->req->params_post->{password} ) {                            # try to authenticate with login and password
        $self->api->authenticate( username => $self->req->params_post->{username}, password => $self->req->params_post->{password} );
    }

    if ( my $uid = $self->api->is_authenticated ) {
        my $res = $self->res;

        # set session cookie only if has session
        $res->add_cookies( $self->session_cookie_name => { value => $self->api->sid, encrypt_ip => $self->bind_session_to_ip } ) if $self->api->has_sid;

        if ( $self->req->params_get->{continue} ) {
            $res->set_status(307);
            $res->add_headers( LOCATION => $self->req->params_get->{continue} );
        }

        return $res;    # authenticated successfully
    }
    else {
        return $self->res->set_status(403);    # 403 - Forbidden, authentication failure
    }
}

sub _auth_signout {
    my $self = shift;

    my $res = $self->res->remove_cookies( $self->session_cookie_name );

    if ( $self->req->params_get->{continue} ) {
        $res->set_status(307);
        $res->add_headers( LOCATION => $self->req->params_get->{continue} );
    }

    # physically remove SID
    $self->api->signout if $self->api->is_authenticated && $self->api->has_sid;

    return $res;
}

sub _api_map {
    my $self = shift;

    return $self->api->get_api_map;
}

sub _api_map_html {
    my $self = shift;

    my $api_map = $self->api->get_api_map;

    return $self->render( 'api_map.html', { api_map => $api_map } );
}

sub _api_class_js {
    my $self = shift;

    if ( !$self->api->is_authenticated ) {
        return $self->res->set_status(307)->add_headers( LOCATION => '/api/signin/?continue=' . P->data->to_uri( $self->req->env->{REQUEST_URI} ) );
    }

    my $js = $self->api->get_api_class_js(
        path  => P->file->path( $self->path->dirname )->canonpath,
        class => $self->path->filename_base,
    );

    if ($js) {
        return $self->res($js)->set_headers( CONTENT_TYPE => 'application/javascript' );
    }
    else {
        return $self->res->set_status(404);
    }
}

sub _api_call {
    my $self = shift;

    my $is_multipart;
    my $call;

    if ( $self->req->content_type =~ m[\Aapplication/json]sm ) {    # simple API call without uploads
        $call = Pcore::API::Call->new( $self->req->json );
    }
    elsif ( $self->req->content_type =~ m[\Aapplication/x-www-form-urlencoded]sm ) {    # request from ext.Direct client via HTTP form submit without uploads, only one transaction can be present at once

        # convert Ext.Direct formHandler params, uploads can't be transferred with this request type
        my $params = $self->_get_ext_direct_params;

        $call = Pcore::API::Call->new($params);
    }
    elsif ( $self->req->content_type =~ m[\Amultipart/form-data]sm ) {
        $is_multipart = 1;

        if ( $self->req->params_post->{extActions} ) {                                  # request from perl client, many transactions with uploads allowed at once
            my $json = P->data->decode( $self->req->params_post->{extActions}->[0] );

            $call = Pcore::API::Call->new($json);

            # attach uploads to actions
            if ( $self->req->uploads ) {
                for my $pair ( P->list->pairs( $self->req->uploads->@* ) ) {
                    if ( exists $pair->value->headers->{TID} ) {
                        $call->action( $pair->value->headers->{TID} )->add_uploads( $pair->key, $pair->value );
                    }
                }
            }
        }
        else {    # request from ext.Direct client via HTTP form submit with uploads, only one transaction with uploads can be present at once

            # convert Ext.Direct formHandler params
            my $params = $self->_get_ext_direct_params;

            $call = Pcore::API::Call->new($params);

            # attach uploads to action
            $call->action->add_uploads( $self->req->uploads ) if $self->req->uploads;
        }
    }
    else {
        return $self->res->set_status(405);
    }

    my $res_call = $self->api->call($call);

    if ($is_multipart) {
        return q[<textarea>], $res_call, q[</textarea>];
    }
    else {
        return $res_call;
    }
}

sub _api_app {
    my $self = shift;

    if ( !$self->api->is_authenticated ) {
        return $self->res->set_status(307)->add_headers( LOCATION => '/api/signin/?continue=' . P->data->to_uri( $self->req->env->{REQUEST_URI} ) );
    }

    my $ext_theme  = $self->ext_theme;
    my $ext_locale = $self->ext_locale;

    my $ext_app_ns = $self->app->name_camel_case . 'Api';

    my $ext_api_map = P->hash->merge( $DEFAULT_API, $self->api->get_api_map );
    $ext_api_map->{namespace} = $self->app->name;

    my $loader_path = {
        q[*]        => q[.],
        Pcore       => '/static/sencha/ext/pcore',
        Ext         => '/static/sencha/ext/src',
        'Ext.ux'    => '/static/sencha/ext/ux',
        $ext_app_ns => q[.],
    };

    my $resources = {
        INDEX => { title => $self->ext_title, },
        ext   => {
            loader_path    => P->text->mark_raw( P->data->to_json( $loader_path, readable => $self->app->env_is_devel )->$* ),
            app_ns         => $ext_app_ns,
            api_map        => P->text->mark_raw( P->data->to_json( $ext_api_map, readable => $self->app->env_is_devel )->$* ),
            viewport_class => $ext_app_ns . '.index.Viewport',
            locale         => $ext_locale,
        },
        devel => $self->app->env_is_devel,
    };

    if ( $self->app->env_is_devel ) {
        $resources->{ext}->{extjs}     = '/static/sencha/ext/build/ext-all-debug.js';
        $resources->{ext}->{theme_css} = qq[/static/sencha/ext/build/packages/ext-theme-$ext_theme/build/resources/ext-theme-$ext_theme-all-debug.css];
        $resources->{ext}->{theme_js}  = qq[/static/sencha/ext/build/packages/ext-theme-$ext_theme/build/ext-theme-$ext_theme-debug.js];
        $resources->{ext}->{locale_js} = qq[/static/sencha/ext/build/packages/ext-locale/build/ext-locale-$ext_locale-debug.js];
    }
    else {
        $resources->{ext}->{extjs}     = '/static/sencha/ext/build/ext-all.js';
        $resources->{ext}->{theme_css} = qq[/static/sencha/ext/build/packages/ext-theme-$ext_theme/build/resources/ext-theme-$ext_theme-all.css];
        $resources->{ext}->{theme_js}  = qq[/static/sencha/ext/build/packages/ext-theme-$ext_theme/build/ext-theme-$ext_theme.js];
        $resources->{ext}->{locale_js} = qq[/static/sencha/ext/build/packages/ext-locale/build/ext-locale-$ext_locale.js];
    }

    return $self->render( 'sencha/index-extjs.html', $resources );
}

sub _get_ext_direct_params {
    my $self = shift;

    my $post_params = $self->req->params_post->normalize;

    delete $post_params->{extUpload};    # this param tell, that API call has uploads, used only from ExtDirect calls

    my $params = {
        tid    => delete $post_params->{extTID},
        action => delete $post_params->{extAction},
        method => delete $post_params->{extMethod},
        type   => delete $post_params->{extType},
        data   => $post_params,                       # all other POST params treated as named params hash ref
    };

    return $params;
}

sub auto_auth {
    my $self = shift;

    my $res = {
        token => undef,
        sid   => undef,
    };

    if ( $self->req->params->{_token} ) {
        $res->{token} = $self->req->params->{_token};
    }
    elsif ( $self->req->auth_challenge_is('TOKEN') ) {
        $res->{token} = $self->req->auth->{token};
    }
    elsif ( $self->req->cookies->{ $self->session_cookie_name } ) {
        $res->{sid} = $self->req->cookies->{ $self->session_cookie_name } . q[];
    }

    return $res;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 31                   │ Subroutines::ProhibitExcessComplexity - Subroutine "run" with high complexity score (24)                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 116, 140             │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
