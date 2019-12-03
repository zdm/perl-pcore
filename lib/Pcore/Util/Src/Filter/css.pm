package Pcore::Util::Src::Filter::css;

use Pcore -class, -res;

with qw[Pcore::Util::Src::Filter];

sub decompress ($self) {
    my $res = $self->filter_prettier('--parser=css');

    return $res;
}

sub compress ($self) {
    my $res = $self->filter_css_packer;

    return $res;
}

sub filter_css_packer ($self) {
    require CSS::Packer;

    state $packer = CSS::Packer->init;

    $packer->minify( \$self->{data}, { compress => 'minify' } );

    return res 200;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Src::Filter::css

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
