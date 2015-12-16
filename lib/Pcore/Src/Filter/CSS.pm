package Pcore::Src::Filter::CSS;

use Pcore -class;
use CSS::Packer qw[];

# CSS::Compressor();

with qw[Pcore::Src::Filter];

sub decompress ($self) {
    my $packer = CSS::Packer->init;

    $packer->{old_declaration_replacement} = $packer->{declaration}->{reggrp_data}->[0]->{replacement};

    $packer->{declaration}->{reggrp_data}->[0]->{replacement} = sub {
        return q[ ] x 4 . $packer->{old_declaration_replacement}->(@_);
    };

    $packer->{_reggrp_declaration} = Regexp::RegGrp->new( { reggrp => $packer->{declaration}->{reggrp_data} } );

    $self->buffer->$* = $packer->minify( $self->buffer, { compress => 'pretty' } );    ## no critic qw[Variables::RequireLocalizedPunctuationVars]

    return 0;
}

sub compress ($self) {
    $self->buffer->$* = CSS::Packer->init->minify( $self->buffer, { compress => 'minify' } );    ## no critic qw[Variables::RequireLocalizedPunctuationVars]

    return 0;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Src::Filter::CSS

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
