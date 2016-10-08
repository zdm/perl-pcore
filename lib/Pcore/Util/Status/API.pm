package Pcore::Util::Status::API;

use Pcore -class;

with qw[Pcore::Util::Status::Role];

sub TO_DATA ($self) {
    my $dump = { $self->%* };

    delete $dump->{status_reason};

    return $dump;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Status::API

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
