package Pcore::Util::Src::Filter::json;

use Pcore -class, -res;

with qw[Pcore::Util::Src::Filter];

sub decompress ($self) {
    my $data = P->data->from_json( $self->{data} );

    $self->{data} = P->data->to_json( $data, readable => 1 );

    return res 200;
}

sub compress ($self) {
    my $data = P->data->from_json( $self->{data} );

    $self->{data} = P->data->to_json( $data, readable => 0 );

    return res 200;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Src::Filter::json

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
