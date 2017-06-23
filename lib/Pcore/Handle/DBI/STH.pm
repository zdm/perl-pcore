package Pcore::Handle::DBI::STH;

use Pcore -class;

has id    => ( is => 'ro', isa => Str, required => 1 );
has query => ( is => 'ro', isa => Str, required => 1 );

has IS_STH => ( is => 'ro', isa => Bool, default => 1, init_arg => undef );

P->init_demolish(__PACKAGE__);

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Handle::DBI::STH

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
