package Pcore::JS::Generator::Raw;

use Pcore -class;

with qw[Pcore::JS::Generator::Base];

has body => ( is => 'ro', isa => Str, required => 1 );

no Pcore;

sub as_js {
    my $self = shift;

    return $self->body;
}

1;
__END__
=pod

=encoding utf8

=cut
