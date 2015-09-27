package Pcore::Util::URI::http;    ## no critic qw[NamingConventions::Capitalization]

use Pcore qw[-class];

extends qw[Pcore::Util::URI];

has '+default_port' => ( default => 80 );

around _prebuild_uri => sub ( $orig, $self, $uri, $base ) {
    $uri->{path} = q[/] if $uri->{has_authority} && $uri->{path} eq q[];

    return $self->$orig( $uri, $base );
};

no Pcore;

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::URI::http

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
