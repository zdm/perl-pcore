package Pcore::Util::Src::Filter::yaml;

use Pcore -class, -res;

with qw[Pcore::Util::Src::Filter];

sub decompress ($self) {
    my $data = P->data->from_yaml( $self->{data} );

    $self->{data}->$* = P->data->to_yaml($data);

    return res 200;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Src::Filter::yaml

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
