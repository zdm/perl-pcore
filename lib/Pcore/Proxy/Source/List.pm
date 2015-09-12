package Pcore::Proxy::Source::List;

use Pcore qw[-class];

with qw[Pcore::Proxy::Source];

has proxies => ( is => 'ro', isa => ArrayRef [Str], required => 1 );

has '+load_timeout' => ( default => 0 );

no Pcore;

sub load ( $self, $cb ) {
    $cb->( $self->proxies );

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Proxy::Source::List

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
