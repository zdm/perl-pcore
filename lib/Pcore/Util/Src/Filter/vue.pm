package Pcore::Util::Src::Filter::vue;

use Pcore -class, -res;
use Pcore::Util::Text qw[rcut_all encode_utf8];

with qw[Pcore::Util::Src::Filter];

# TODO run lint
sub decompress ($self) {
    my $res = $self->filter_prettier('--parser=vue');

    return $res;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Src::Filter::vue

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
