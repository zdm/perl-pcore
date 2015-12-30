package Pcore::HTTP::Response;

use Pcore -class;

extends qw[Pcore::HTTP::Message];

# pseudo-headers
has url => ( is => 'ro', isa => Str | Object, writer => 'set_url' );
has version => ( is => 'ro', isa => Num, writer => 'set_version', init_arg => undef );
has reason  => ( is => 'ro', isa => Str, writer => 'set_reason',  init_arg => undef );

has is_http_redirect => ( is => 'ro', isa => Bool, writer => 'set_is_http_redirect', default => 0, init_arg => undef );
has redirect => ( is => 'lazy', isa => ArrayRef, default => sub { [] }, init_arg => undef );

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::Response

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
