package Pcore::Util::Response::Status;

use Pcore -class;

with qw[Pcore::Util::Status::Role];

sub TO_DATA ($self) {
    my $dump = { $self->%* };

    # remove internal keys
    delete $dump->{status_reason};

    $dump->{api_status} = delete $dump->{status};
    $dump->{api_reason} = delete $dump->{reason};

    # defined response type
    if ( $self->is_success ) {
        $dump->{type} = 'rpc';
    }
    else {
        $dump->{type} = 'exception';
        $dump->{message} //= $dump->{api_reason};
    }

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
