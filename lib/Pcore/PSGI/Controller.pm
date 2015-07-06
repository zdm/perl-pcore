package Pcore::PSGI::Controller;

use Pcore qw[-role];
use Pcore::Util::UA::Response;

requires qw[run];

has app => ( is => 'ro', isa => ConsumerOf ['Pcore::App::PSGI::Role'], required => 1, weak_ref => 1 );
has path => ( is => 'ro', isa => InstanceOf ['Pcore::Util::File::Path'], required => 1 );
has x_accel_locations => ( is => 'lazy', isa => HashRef, init_arg => undef );

our $NGINX_TMPL = <<'TT2NGINX';
    location <: $location :> {
        error_page 418 = @backend;
        return 418;
    }
TT2NGINX

sub _build_nginx_cfg {
    my $self = shift;

    my $params = { location => $self->path->base, };

    return $self->render( \$NGINX_TMPL, $params );
}

sub _build_x_accel_locations {
    my $self = shift;

    return {};
}

# SHORTCUTS
sub h {
    my $self = shift;

    return $self->app->h;
}

sub router {
    my $self = shift;

    return $self->app->router;
}

sub req {
    my $self = shift;

    return $self->app->req;
}

sub res {
    my $self = shift;

    return Pcore::Util::UA::Response->new_response(@_);
}

# API
sub api {
    my $self = shift;

    return $self->app->api;
}

# TMPL
sub render {
    my $self = shift;

    return $self->app->tmpl->renderer->render(@_);
}

1;
__END__
=pod

=encoding utf8

=cut
