package Pcore::Util::URI::ssh;    ## no critic qw[NamingConventions::Capitalization]

use Pcore -class;

extends qw[Pcore::Util::URI];

has '+is_secure'    => ( default => 1 );
has '+default_port' => ( default => 22 );

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::URI::ssh

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
