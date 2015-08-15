package Pcore::AppX::API;

use Pcore qw[-class];

with qw[Pcore::AppX];

has _api_backend => ( is => 'rwp', isa => ConsumerOf ['Pcore::API::Backend'], predicate => 1, init_arg => undef );

no Pcore;

sub BUILD {
    my $self = shift;

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
sub _build_cfg {
    my $self = shift;

    my $cfg = {
        addr        => undef,
        h_name      => undef,
        session_ttl => 60 * 30,
    };

    return $cfg;
}

sub _create_local_cfg {
    my $self = shift;

    return $self->cfg;
}

# preload API map
sub app_run {
    my $self = shift;

    $self->_api_backend->preload_api_map if $self->_has_api_backend;

    return;
}

# scan and sync API map
sub app_deploy {
    my $self = shift;

    $self->_api_backend->deploy_api if $self->_has_api_backend;

    return;
}

sub app_reset {
    my $self = shift;

    $self->_api_backend->end_session if $self->_has_api_backend;

    return;
}

# TODO
# API backend signout
# return unless defined $self->{_backend};    # _backend can be destroyed first during global destruction
sub AUTOLOAD {    ## no critic qw[ClassHierarchies::ProhibitAutoloading]
    my $self = shift;

    my $method = our $AUTOLOAD =~ s/\A.*:://smr;

    return $self->_api_backend->$method(@_);
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 57                   │ Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_create_local_cfg' declared but not │
## │      │                      │ used                                                                                                           │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
