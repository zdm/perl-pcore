package Pcore::Util::Path1;

use Pcore -class, -const, -res;
use IO::AIO qw[];
use AnyEvent::IO qw[];
use Clone qw[];

use overload
  q[""]    => sub { $_[0]->{to_string} },
  fallback => 1;

with qw[Pcore::Util::Result::Status Pcore::Util::Path1::Stat Pcore::Util::Path1::Dir Pcore::Util::Path1::Poll];

has to_string => ();

around new => sub ( $orig, $self, $path ) {
    $self = bless { to_string => $path }, __PACKAGE__;

    return $self;
};

sub clone ($self) {
    return Clone::clone($self);
}

# sub TO_DUMP {
#     my $self = shift;

#     my $res;
#     my $tags;

#     $res = qq[path: "$self->{to_string}"];

#     # $res .= qq[\nMIME type: "] . $self->mime_type . q["] if $self->mime_type;

#     return $res, $tags;
# }

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Path1

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
