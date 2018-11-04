package Pcore::Src1::css;

use Pcore -class, -res;
use CSS::Packer qw[];

with qw[Pcore::Src1::Filter];

my $COMPRESSOR = CSS::Packer->init;

my $DECOMPRESSOR = do {
    my $packer = CSS::Packer->init;

    $packer->{old_declaration_replacement} = $packer->{declaration}->{reggrp_data}->[0]->{replacement};

    $packer->{declaration}->{reggrp_data}->[0]->{replacement} = sub {
        return q[ ] x 4 . $packer->{old_declaration_replacement}->(@_);
    };

    $packer->{_reggrp_declaration} = Regexp::RegGrp->new( { reggrp => $packer->{declaration}->{reggrp_data} } );

    $packer;
};

sub decompress ($self) {
    $DECOMPRESSOR->minify( $self->{data}, { compress => 'pretty' } );

    return res 200;
}

sub compress ($self) {
    $COMPRESSOR->minify( $self->{data}, { compress => 'minify' } );

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
