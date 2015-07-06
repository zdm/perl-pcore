package Pcore::PSGI::Request;

use Pcore qw[-class];
use URI qw[];
use HTTP::Body qw[];

with qw[Pcore::AppX Pcore::Util::UA::Headers Pcore::Util::UA::Uploads];

has uploads_dir => ( is => 'ro', isa => Str, default => $PROC->{TEMP_DIR} . 'uploads/' );

has uri         => ( is => 'lazy', isa => InstanceOf ['URI'],                           init_arg => undef );
has params      => ( is => 'lazy', isa => InstanceOf ['Pcore::Util::Hash::Multivalue'], init_arg => undef );
has params_get  => ( is => 'lazy', isa => InstanceOf ['Pcore::Util::Hash::Multivalue'], init_arg => undef );
has params_post => ( is => 'lazy', isa => InstanceOf ['Pcore::Util::Hash::Multivalue'], init_arg => undef );
has json => ( is => 'lazy', isa => Str | HashRef | ArrayRef, init_arg => undef );
has content => ( is => 'lazy', isa => Maybe [ InstanceOf ['HTTP::Body'] ], init_arg => undef );
has content_raw => ( is => 'lazy', isa => Maybe [ScalarRef], init_arg => undef );
has path => ( is => 'lazy', isa => InstanceOf ['Pcore::Util::File::Path'], init_arg => undef );
has remote_addr => ( is => 'lazy', isa => Str, init_arg => undef );
has country     => ( is => 'lazy', isa => Str, init_arg => undef );
has ua => ( is => 'lazy', isa => Maybe [ InstanceOf ['HTTP::BrowserDetect'] ], init_arg => undef );
has browser         => ( is => 'lazy', isa => Str,  init_arg => undef );
has browser_ver     => ( is => 'lazy', isa => Str,  init_arg => undef );
has os              => ( is => 'lazy', isa => Str,  init_arg => undef );
has scheme          => ( is => 'lazy', isa => Str,  init_arg => undef );
has method          => ( is => 'lazy', isa => Str,  init_arg => undef );
has is_secure       => ( is => 'lazy', isa => Bool, init_arg => undef );
has content_length  => ( is => 'lazy', isa => Str,  init_arg => undef );
has content_type    => ( is => 'lazy', isa => Str,  init_arg => undef );
has x_accel_support => ( is => 'lazy', isa => Bool, init_arg => undef );
has auth => ( is => 'lazy', isa => Maybe [HashRef], init_arg => undef );

has _headers_builded => ( is => 'rw', isa => Bool, default => 0, init_arg => undef );
has _uploads_builded => ( is => 'rw', isa => Bool, default => 0, init_arg => undef );

before headers => sub {
    my $self = shift;

    return if $self->_headers_builded;

    $self->_headers_builded(1);

    my $headers;

    for my $header ( keys $self->env->%* ) {
        if ( $header =~ /\AHTTP_(.+)/sm ) {
            push $headers->@*, $1 => $self->env->{$header};
        }
    }

    $self->add_headers($headers);

    $self->decode_cookies( secret => $self->app->cfg->{SECRET}, remote_addr => $self->remote_addr );

    return;
};

before cookies => sub {
    my $self = shift;

    return if $self->_headers_builded;

    $self->headers;

    return;
};

before uploads => sub {
    my $self = shift;

    return if $self->_uploads_builded;

    $self->_uploads_builded(1);

    if ( defined $self->content ) {
        my @uploads;
        my $content_uploads = $self->content->upload;

        for my $upload_name ( keys $content_uploads->%* ) {
            my $upload_name_utf8 = P->text->decode($upload_name)->$*;
            my $uploads = ref $content_uploads->{$upload_name} eq 'ARRAY' ? $content_uploads->{$upload_name} : [ $content_uploads->{$upload_name} ];

            for ( $uploads->@* ) {
                push @uploads,
                  $upload_name_utf8 => [
                    [   $_->{headers}->%*,
                        path     => $_->{tempname},
                        filename => $_->{filename},
                    ]
                  ];
            }
        }

        $self->add_uploads(@uploads);
    }

    return;
};

no Pcore;

# APPX
sub _build_appx_reset {
    my $self = shift;

    return 'CLEAR';
}

# ENV
sub env {
    my $self = shift;

    return $self->app->env;
}

sub harakiri {
    my $self = shift;

    $self->env->{'psgix.harakiri.commit'} = 1;
    return;
}

sub finish {
    my $self = shift;

    return propagate('APP::REQ::FINISH');
}

# URI
sub _build_uri {
    my $self = shift;

    my $base = ( $self->env->{'psgi.url_scheme'} || 'http' ) . q[://] . ( $self->headers->{HOST} || ( ( $self->env->{SERVER_NAME} || q[] ) . q[:] . ( $self->env->{SERVER_PORT} || 80 ) ) ) . ( $self->env->{SCRIPT_NAME} || q[/] );

    my $path = $self->env->{PATH_INFO} ? P->data->to_uri( $self->env->{PATH_INFO} ) : q[];
    $path .= q[?] . $self->env->{QUERY_STRING} if defined $self->env->{QUERY_STRING} && $self->env->{QUERY_STRING} ne q[];

    $base =~ s[/\z][]sm if $path =~ m[\A/]sm;

    return URI->new( $base . $path )->canonical;
}

# PATH
sub _build_path {
    my $self = shift;

    my $path = $self->env->{PATH_INFO} ? P->data->from_uri( $self->env->{PATH_INFO} ) : q[/];

    return P->file->path($path);
}

# METHOD
sub _build_method {
    my $self = shift;

    return uc $self->env->{REQUEST_METHOD};
}

sub is_get {
    my $self = shift;

    return $self->method eq 'GET';
}

sub is_post {
    my $self = shift;

    return $self->method eq 'POST';
}

# HEADERS
sub _build_scheme {
    my $self = shift;

    return $self->env->{'psgi.url_scheme'};
}

sub _build_is_secure {
    my $self = shift;

    return $self->scheme eq 'https';
}

sub _build_content_length {
    my $self = shift;

    return $self->env->{CONTENT_LENGTH} // 0;
}

sub _build_content_type {
    my $self = shift;

    return $self->env->{CONTENT_TYPE} // q[];
}

sub _build_x_accel_support {
    my $self = shift;

    if ( $self->headers->{X_ACCEL_SUPPORT} ) {
        return 1;
    }
    else {
        return 0;
    }
}

# PARAMS
sub _build_params {
    my $self = shift;

    my $params = P->hash->multivalue;

    $params->add( $self->params_post );
    $params->add( $self->params_get );

    return $params;
}

sub _build_params_get {
    my $self = shift;

    return P->data->from_uri_query( $self->env->{QUERY_STRING} // q[] );
}

sub _build_params_post {
    my $self = shift;

    my $params = [];

    if ( defined $self->content ) {
        for my $param ( keys $self->content->param->%* ) {
            my $name_utf8 = P->text->decode($param)->$*;

            if ( ref $self->content->param->{$param} eq 'ARRAY' ) {
                for my $val ( $self->content->param->{$param}->@* ) {
                    push $params, $name_utf8 => P->text->decode($val)->$*;
                }
            }
            else {
                push $params, $name_utf8 => P->text->decode( $self->content->param->{$param} )->$*;
            }
        }
    }

    return P->hash->multivalue($params);
}

sub _build_json {
    my $self = shift;

    my $json;

    if ( defined $self->content && ref $self->content eq 'HTTP::Body::OctetStream' && $self->content_type =~ m[\Aapplication/json]sm ) {
        if ( my $buffer = $self->content_raw ) {
            $json = P->data->decode( $buffer->$* );
        }
    }

    return $json || {};
}

# CONTENT
sub _build_content {
    my $self = shift;

    if ( !$self->env->{'psgi.input'} || ( !$self->content_type && !$self->content_length ) ) {    # no Content-Type nor Content-Length -> GET/HEAD
        return;
    }
    else {
        my $content_length = $self->content_length;

        my $content = HTTP::Body->new( $self->content_type, $content_length );
        $content->cleanup(1);                                                                     # unlink uploads on destruction
        P->file->mkpath( $self->uploads_dir, mode => q[rwx------] ) if !-d $self->uploads_dir;
        $content->tmpdir( $self->uploads_dir );

        my $input = $self->env->{'psgi.input'};
        $input->seek( 0, 0 ) if $self->env->{'psgix.input.buffered'};                             # if input is read by middleware/apps beforehand

        my $spin = 0;
        while ($content_length) {
            $input->read( my $chunk, $content_length < 8192 ? $content_length : 8192 );
            my $read = length $chunk;
            $content_length -= $read;
            $content->add($chunk);

            if ( $read == 0 && $spin++ > 2000 ) {
                croak("Bad Content-Length: maybe client disconnect? ($content_length bytes remaining)");
            }
        }

        # rewind handle
        $content->body->seek( 0, 0 ) if defined $content->body;

        return $content;
    }
}

# content_fh not available if multipart/form-data encoding used
# return File::Temp instance
sub content_fh {
    my $self = shift;

    if ( defined $self->content && defined $self->content->body ) {
        return $self->content->body;
    }
    else {
        return;
    }
}

# slurp content from content_fh and store as ScalarRef
sub _build_content_raw {
    my $self = shift;

    if ( my $content_fh = $self->content_fh ) {
        return P->file->read_bin($content_fh);
    }
    else {
        return;
    }
}

# REMOTE_ADDR
# TODO improve X-Trusted-Proxy-Key realtime calculation, use md5($proxy_bind_addr . $secret . $proxy_bind_addr)
sub _build_remote_addr {
    my $self = shift;

    if ( $self->headers->{X_REAL_IP} && $self->headers->{X_TRUSTED_PROXY_KEY} && $self->headers->{X_TRUSTED_PROXY_KEY} eq P->digest->md5_hex( $self->app->cfg->{SECRET} ) ) {
        return $self->headers->{X_REAL_IP}->[0];
    }

    # if ( $self->headers->{X_REAL_IP} && $self->headers->{X_TRUSTED_PROXY_KEY} && $self->headers->{X_TRUSTED_PROXY_KEY} eq P->digest->md5_hex( $self->env->{REMOTE_ADDR} . P->digest->md5_hex( $self->app->cfg->{SECRET} ) . $self->env->{REMOTE_ADDR} ) ) {
    #     return $self->headers->{X_REAL_IP}->[0];
    # }

    return $self->env->{REMOTE_ADDR};
}

sub _build_country {
    my $self = shift;

    return P->geoip->country_code_by_addr( $self->remote_addr );
}

# UA
sub _build_ua {
    my $self = shift;

    if ( $self->headers->{USER_AGENT} ) {
        require HTTP::BrowserDetect;

        return HTTP::BrowserDetect->new( $self->headers->{USER_AGENT} );
    }
    else {
        return;
    }
}

sub _build_browser {
    my $self = shift;

    return defined $self->ua ? $self->ua->browser_string : q[];
}

sub _build_browser_ver {
    my $self = shift;

    return defined $self->ua ? $self->ua->version : q[];
}

sub _build_os {
    my $self = shift;

    return defined $self->ua ? $self->ua->os_string : q[];
}

# AUTH
sub _build_auth {
    my $self = shift;

    my $auth = {
        challenge => undef,
        token     => undef,
        username  => undef,
        password  => undef,
    };

    if ( $self->headers->{AUTHORIZATION} ) {
        ( $auth->{challenge}, $auth->{token} ) = $self->headers->{AUTHORIZATION} =~ /\A(\S+)\s(.*)\z/sm;

        $auth->{challenge} = uc $auth->{challenge};

        if ( $auth->{challenge} eq 'BASIC' ) {
            ( $auth->{username}, $auth->{password} ) = P->data->from_b64_url( $auth->{token} ) =~ /\A(.+)?:(.+)/sm;
        }
        elsif ( $auth->{challenge} eq 'DIGEST' ) {
            for my $field ( split /,\s*/sm, $auth->{token} ) {
                my ( $key, $val ) = $field =~ /\A([^=]+)=(.*)\z/sm;
                $val =~ s/\A"|"\z//smg;    # de-quote value
                $auth->{$key} = P->data->from_uri($val);
            }
        }
    }

    return $auth;
}

sub auth_challenge_is {
    my $self      = shift;
    my $challenge = shift;

    if ( defined $self->auth && $self->auth->{challenge} && $self->auth->{challenge} eq uc $challenge ) {
        return 1;
    }
    else {
        return;
    }
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 45, 79, 86, 231      │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
