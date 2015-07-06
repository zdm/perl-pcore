package Pcore::AnyEvent::Proxy::Source::File;

use Pcore qw[-class];

with qw[Pcore::AnyEvent::Proxy::Source];

has path => ( is => 'ro', isa => Str, required => 1 );
has type => ( is => 'ro', isa => HashRef, default => sub { {} } );

no Pcore;

sub load {
    my $self    = shift;
    my $cv      = shift;
    my $proxies = shift;

    $cv->begin;

    if ( -f $self->path ) {
        for my $addr ( P->file->read_lines( $self->path )->@* ) {
            P->text->trim($addr);

            push $proxies, { $self->type->%*, addr => $addr } if $addr;
        }
    }

    $cv->end;

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 23                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
