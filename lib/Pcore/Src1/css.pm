package Pcore::Src1::css;

use Pcore -class, -res;
use CSS::Packer qw[];

with qw[Pcore::Src1::Filter];

my $PACKER = CSS::Packer->init;

sub decompress ($self) {
    $PACKER->minify( $self->{data}, { compress => 'pretty', indent => 4 } );

    return res 200;
}

sub compress ($self) {
    $PACKER->minify( $self->{data}, { compress => 'minify' } );

    return res 200;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Src1::css

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
