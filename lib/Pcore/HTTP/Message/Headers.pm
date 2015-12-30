package Pcore::HTTP::Message::Headers;

use Pcore -class;
extends qw[Pcore::Util::Hash::Multivalue];

sub to_psgi ($self) {
    my $hash = $self->get_hash;

    my $headers = [];

    for ( keys $hash->%* ) {
        my $header = ( ucfirst lc ) =~ s/_([[:alpha:]])/q[-] . uc $1/smger;

        push $headers->@*, map { ( $header, $_ ) } $hash->{$_}->@*;
    }

    return $headers;
}

sub to_string ($self) {
    my $hash = $self->get_hash;

    my $headers = q[];

    for ( keys $hash->%* ) {
        my $header = ( ucfirst lc ) =~ s/_([[:alpha:]])/q[-] . uc $1/smger;

        for ( $hash->{$_}->@* ) {
            $headers .= $header . q[: ] . $_ . $CRLF;
        }
    }

    return $headers;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 11, 25               │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::Message::Headers

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
