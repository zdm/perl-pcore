package Pcore::Util::URI::https;    ## no critic qw[NamingConventions::Capitalization]

use Pcore -class;

extends qw[Pcore::Util::URI];

with qw[Pcore::Util::URI::Web2];

has '+is_secure'    => ( default => 1 );
has '+default_port' => ( default => 443 );

no Pcore;

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::URI::https

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
