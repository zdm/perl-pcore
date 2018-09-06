package Pcore::CDN::Bucket::local;

use Pcore -class;

with qw[Pcore::CDN::Bucket];

sub get_url ( $self, $path ) {
    return $path;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::CDN::Bucket::local

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
