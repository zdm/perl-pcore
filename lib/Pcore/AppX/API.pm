package Pcore::AppX::API;

use Pcore -class, -autoload;

with qw[Pcore::AppX];

has _api_backend => ( is => 'rwp', isa => ConsumerOf ['Pcore::API::Backend'], predicate => 1, init_arg => undef );

sub BUILD ( $self, $args ) {
    my $api_backend;

    if ( $self->cfg->{addr} ) {    # remote API
        $api_backend = P->class->load('Pcore::API::Backend::Remote')->new( { addr => $self->addr } );
    }
    elsif ( $self->cfg->{h_name} ) {    # local API

        # create App handles
        $self->app->h->app_run;

        my $h_name = $self->cfg->{h_name};
        my $h_obj  = $self->app->h->$h_name;

        my $backend = $h_obj->dbd_type;

        my $new_args = {
            app    => $self->app,
            h_name => $h_name,          # API handle name
        };

        $new_args->{session_ttl} = $self->cfg->{session_ttl} if $self->cfg->{session_ttl};

        $api_backend = P->class->load( $backend, ns => 'Pcore::API::Backend::Local' )->new($new_args);
    }

    $self->_set__api_backend($api_backend) if $api_backend;

    return;
}

# APPX
sub _build_cfg ($self) {
    my $cfg = {
        addr        => undef,
        h_name      => undef,
        session_ttl => 60 * 30,
    };

    return $cfg;
}

sub _create_local_cfg ($self) {
    return $self->cfg;
}

# preload API map
sub app_run ($self) {
    $self->_api_backend->preload_api_map if $self->_has_api_backend;

    return;
}

# scan and sync API map
sub app_deploy ($self) {
    $self->_api_backend->deploy_api if $self->_has_api_backend;

    return;
}

sub app_reset ($self) {
    $self->_api_backend->end_session if $self->_has_api_backend;

    return;
}

# TODO
# API backend signout
# return unless defined $self->{_backend};    # _backend can be destroyed first during global destruction
sub _AUTOLOAD ( $self, $method, @ ) {
    return <<"PERL";
        sub {
            my \$self = shift;

            return \$self->_api_backend->$method(\@_);
        };
PERL
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │                      │ Subroutines::ProhibitUnusedPrivateSubroutines                                                                  │
## │      │ 51                   │ * Private subroutine/method '_create_local_cfg' declared but not used                                          │
## │      │ 78                   │ * Private subroutine/method '_AUTOLOAD' declared but not used                                                  │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AppX::API

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
