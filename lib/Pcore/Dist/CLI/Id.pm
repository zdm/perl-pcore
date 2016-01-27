package Pcore::Dist::CLI::Id;

use Pcore -class;

with qw[Pcore::Dist::CLI];

sub CLI ($self) {
    return {
        abstract => 'show distribution info',
        opt      => { pcore => { desc => 'show info about currently used Pcore distribution', }, };
        ,
    };
}

sub CLI_RUN ( $self, $opt, $arg, $rest ) {
    $self->new->run( $opt->{pcore} );

    return;
}

sub run ( $self, $pcore = 0 ) {
    my $tmpl = <<'TMPL';
name: <: $dist.name :>
version: <: $dist.version :>
revision: <: $dist.revision :>
installed: <: $dist.is_installed :>
module_name: <: $dist.module.name :>
root: <: $dist.root :>
share_dir: <: $dist.share_dir :>
lib_dir: <: $dist.module.lib :>
TMPL

    say P->tmpl->render( \$tmpl, { dist => $pcore ? $ENV->pcore : $self->dist } )->$*;

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::CLI::Id - show different distribution info

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
