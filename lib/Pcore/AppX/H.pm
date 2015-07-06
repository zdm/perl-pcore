package Pcore::AppX::H;

use Pcore qw[-class];

with qw[Pcore::AppX];
extends qw[Pcore::Core::H::Cache];

# H
around _build__h_cache => sub {
    my $orig = shift;
    my $self = shift;

    $self->app->ev->register( 'APP::REQ::FINISH', \&_h_ev_req_finish, args => [ \$self ] );

    return $self->$orig;
};

around _build__h_supported_events => sub {
    my $orig = shift;
    my $self = shift;

    my $res = $self->$orig;

    $res->{REQ_FINISH} = 1;

    return $res;
};

sub _h_ev_req_finish {
    my $ev   = shift;
    my $self = ${ shift @_ };

    if ($self) {
        $self->run_event('REQ_FINISH');
    }
    else {
        $ev->remove;
    }

    return;
}

# APPX
sub _create_local_cfg {
    my $self = shift;

    return $self->cfg;
}

sub app_run {
    my $self = shift;

    for my $h ( keys %{ $self->cfg } ) {
        $self->add(
            $h => $self->cfg->{$h}->{CLASS},
            %{ $self->cfg->{$h} },
        );
    }

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 44                   │ Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_create_local_cfg' declared but not │
## │      │                      │ used                                                                                                           │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
