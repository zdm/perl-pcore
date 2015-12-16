package Pcore::AppX::Tmpl;

use Pcore -class;

with qw[Pcore::AppX];

has renderer => ( is => 'ro', isa => InstanceOf ['Pcore::Util::Template'], default => sub { return P->tmpl }, init_arg => undef );

sub app_run ($self) {
    $self->renderer;

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AppX::Tmpl

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
