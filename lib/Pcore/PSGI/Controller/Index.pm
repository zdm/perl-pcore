package Pcore::PSGI::Controller::Index;

use Pcore qw[-role];

with qw[Pcore::PSGI::Controller Pcore::PSGI::Controller::Static];

# TODO
# improve X-Trusted-Proxy-Key realtime calculation, use md5($proxy_bind_addr . $secret . $proxy_bind_addr)
our $NGINX_TMPL = <<'TT2NGINX';
    location @backend {
        proxy_pass       <: $proxy_pass :>;
        proxy_set_header Host $host;
        proxy_set_header X-Accel-Support 1;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Trusted-Proxy-Key <: $trusted_proxy_key :>;
    }

    location =<: $self.path.base :> {
        error_page 418 = @backend;
        return 418;
    }

    location <: $self.path.base :> {
        error_page 418 = @<: $self.path.base :>0;
        return 418;
    }
: for $self.static_root -> $root {

    location @<: $self.path.base :><: $~root.index :> {
        root <: $root :>;
: if $self.static_no_cache {
        add_header Cache-Control "no-cache no-store max-age=0 s-maxage=0 must-revalidate proxy-revalidate";
: }
: else if $self.static_cache_control.size() {
        add_header Cache-Control "<: $self.static_cache_control.join(' ') :>";
: }
        try_files $uri <: if $~root.is_last { "=404" } else { "@" ~ $self.path.base ~ ($~root.index + 1) } :>;
    }
: }
TT2NGINX

sub _build_nginx_cfg {
    my $self = shift;

    my $params = {
        self              => $self,
        proxy_pass        => P->uri( $self->app->server_cfg->{listen}->[0] )->to_nginx('http'),
        trusted_proxy_key => P->digest->md5_hex( $self->app->cfg->{SECRET} ),
    };

    return $self->render( \$NGINX_TMPL, $params );
}

around run => sub {
    my $orig = shift;
    my $self = shift;

    if ( $self->path->is_file ) {
        return $self->req->set_status(405) unless $self->req->is_get;

        return $self->serve_static_root( $self->path, $self->static_root );
    }
    else {
        return $self->$orig(@_);
    }
};

1;
__END__
=pod

=encoding utf8

=cut
