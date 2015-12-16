package Pcore::AE::Handle::ProxyPool::Source::List;

use Pcore -class;

with qw[Pcore::AE::Handle::ProxyPool::Source];

has proxy => ( is => 'ro', isa => ArrayRef [Str], required => 1 );

has '+load_timeout' => ( default => 0, init_arg => undef );

no Pcore;

sub load ( $self, $cb ) {
    $cb->( $self->proxy );

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AE::Handle::ProxyPool::Source::List

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
