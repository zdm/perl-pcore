package Pcore::Util::URI::Path;

use Pcore;
use base qw[Pcore::Util::Path];

use overload    #
  q[""] => sub {
    return $_[0]->to_uri;
  },
  q[cmp] => sub {
    my $self = shift;

    return $_[1] ? $_[0] cmp $self->to_uri : $self->to_uri cmp $_[0];
  },
  q[~~] => sub {
    my $self = shift;

    return $_[1] ? $_[0] ~~ $self->to_uri : $self->to_uri ~~ $_[0];
  },
  fallback => undef;

no Pcore;

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::URI::Path

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
