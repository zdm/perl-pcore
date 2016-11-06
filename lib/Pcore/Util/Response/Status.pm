package Pcore::Util::Response::Status;

use Pcore -class;

with qw[Pcore::Util::Status::Role];

sub TO_DATA ($self) {
    my $dump = { $self->%* };

    # remove internal keys
    delete $dump->{status_reason};

    # add "success" key
    $dump->{success} = $self ? $TRUE : $FALSE if !exists $dump->{success};

    return $dump;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Response::Status

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
