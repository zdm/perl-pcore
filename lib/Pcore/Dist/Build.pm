package Pcore::Dist::Build;

use Pcore qw[-class];
use Module::CPANfile;

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

# TODO commands:
# new
# test --release --smoke
# smoke
# clean
# deploy
# par
# release --major, --minor, --bugfix
# wiki
sub run ( $self, $cmd ) {
    my $method = '_cmd_' . $cmd;

    if ( $self->can($method) ) {
        $self->$method;
    }

    return;
}

sub _cmd_build ($self) {
    my $cpanfile = Module::CPANfile->load('cpanfile');

    say dump $cpanfile;

    # TODO build workflow
    # - validate dist.perl config;
    # - generate README.md, Build.PL, META.json, LICENSE;
    # - copy all files to the temp build dir;
    # - generate MANIFEST;

    # say dump $self->dist->hg->cmd('id', '-inbt');

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 41                   │ Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_cmd_build' declared but not used   │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::Build

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
