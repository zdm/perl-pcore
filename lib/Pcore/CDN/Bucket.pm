package Pcore::CDN::Bucket;

use Pcore -role;
use overload '&{}' => sub ( $self, @ ) {
    return sub { $self->get_url(@_) }
  },
  fallback => 1;

requires qw[upload];

has prefix => ( init_arg => undef );

sub get_url ( $self, $path ) { return $self->{prefix} . $path }

sub get_nginx_cfg ($self) {return}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::CDN::Bucket

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
