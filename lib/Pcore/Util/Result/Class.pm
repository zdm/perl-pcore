package Pcore::Util::Result::Class;

use Pcore -class;
use overload
  bool     => sub { substr( $_[0]->{status}, 0, 1 ) == 2 },
  '0+'     => sub { $_[0]->{status} },
  q[""]    => sub {"$_[0]->{status} $_[0]->{reason}"},
  fallback => 1;

with qw[Pcore::Util::Result::Role];

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Result::Class

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
