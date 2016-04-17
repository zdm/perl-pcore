package Pcore::AppX::H;

use Pcore -class;

with qw[Pcore::AppX];

extends qw[Pcore::Core::H::Cache];

# H
around _build__h_cache => sub ( $orig, $self ) {
    $self->app->ev->register( 'APP::REQ::FINISH', \&_h_ev_req_finish, args => [ \$self ] );

    return $self->$orig;
};

around _build__h_supported_events => sub ( $orig, $self ) {
    my $res = $self->$orig;

    $res->{REQ_FINISH} = 1;

    return $res;
};

sub _h_ev_req_finish ( $ev, $self_ref ) {
    if ( $self_ref->$* ) {
        $self_ref->$*->run_event('REQ_FINISH');
    }
    else {
        $ev->remove;
    }

    return;
}

# APPX
sub _create_local_cfg ($self) {
    return $self->cfg;
}

sub app_run ($self) {
    for my $h ( keys $self->cfg->%* ) {
        $self->add(
            $h => $self->cfg->{$h}->{CLASS},
            $self->cfg->{$h}->%*,
        );
    }

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 36                   | Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_create_local_cfg' declared but not |
## |      |                      |  used                                                                                                          |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 41, 44               | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AppX::H

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
