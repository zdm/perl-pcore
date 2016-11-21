package Pcore::Util::Response::Status;

use Pcore -class;

with qw[Pcore::Util::Status::Role];

sub TO_DATA ($self) {
    my $dump = {
        tid    => $self->{tid},
        result => {
            'status' => $self->{status},
            reason   => $self->{reason},
        },
    };

    $dump->{result}->{data}  = $self->{result} if defined $self->{result};
    $dump->{result}->{total} = $self->{total}  if defined $self->{total};

    # define response type
    if ( $self->is_success ) {
        $dump->{type} = 'rpc';
        $dump->{message} = $self->{message} if $self->{message};
    }
    else {
        $dump->{type} = 'exception';
        $dump->{message} = $self->{message} // $self->{reason};
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
