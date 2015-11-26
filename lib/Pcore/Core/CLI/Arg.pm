package Pcore::Core::CLI::Arg;

use Pcore qw[-class];
use Pcore::Core::CLI::Type;

has name => ( is => 'ro', isa => Str, required => 1 );
has isa => ( is => 'ro', isa => Maybe [ CodeRef | RegexpRef | ArrayRef | Enum [ keys $Pcore::Core::CLI::Type::TYPE->%* ] ] );
has required => ( is => 'ro', isa => Bool, default => 1 );
has slurpy   => ( is => 'ro', isa => Bool, default => 0 );

has type_desc => ( is => 'lazy', isa => Str, init_arg => undef );
has spec      => ( is => 'lazy', isa => Str, init_arg => undef );

no Pcore;

sub _build_type_desc ($self) {
    return uc $self->name =~ s/_/-/smgr;
}

sub validate ( $self, $val ) {
    return if !$self->type;

    return Pcore::Core::CLI::Type->validate( $val, $self->type );
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 7                    │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::CLI::Arg

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
