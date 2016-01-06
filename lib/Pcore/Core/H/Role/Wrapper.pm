package Pcore::Core::H::Role::Wrapper;

use Pcore -role, -autoload;

with qw[Pcore::Core::H::Role];

requires qw[h_connect];

has h => ( is => 'lazy', builder => 'h_connect', predicate => 'h_is_connected', clearer => 1, init_arg => undef );

around h_disconnect => sub {
    my $orig = shift;
    my $self = shift;

    if ( $self->h_is_connected ) {
        $self->$orig if defined $self->{h};

        $self->clear_h;
    }

    return;
};

sub _AUTOLOAD ( $self, $method, @ ) {
    return <<"PERL";
        sub {
            my \$self = shift;

            return \$self->h->$method(\@_);
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
## │    3 │ 24                   │ Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_AUTOLOAD' declared but not used    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::H::Role::Wrapper

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
