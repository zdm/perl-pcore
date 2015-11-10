package Pcore::Core::Build;

use Pcore qw[-class];
use Pcore::Core::Dist;

has dist_root => ( is => 'ro', isa => Str, required => 1 );

has dist => ( is => 'lazy', init_arg => undef );

around new => sub ( $orig, $self, $dist_root ) {
    $dist_root = P->path($dist_root) if !ref $dist_root;

    return $self->$orig( { dist_root => $dist_root->realpath->to_string } );
};

no Pcore;

sub _build_dist ($self) {
    return Pcore::Core::Dist->new( $self->dist_root );
}

sub run ( $self, $cmd ) {
    my $method = '_cmd_' . $cmd;

    if ( $self->can($method) ) {
        $self->$method;
    }

    return;
}

sub _cmd_build ($self) {
    say 123;

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 32                   │ Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_cmd_build' declared but not used   │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Build

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
