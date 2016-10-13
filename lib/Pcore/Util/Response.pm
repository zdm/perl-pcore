package Pcore::Util::Response;

use Pcore -class, -export => [qw[status]];
use Pcore::Util::Response::Status;

sub status ( $status, @ ) {
    my %args = @_ == 2 ? ( result => $_[1] ) : splice @_, 1;

    if ( ref $status eq 'ARRAY' ) {
        $args{status} = $status->[0];

        if ( ref $status->[1] eq 'HASH' ) {
            $args{reason} = Pcore::Util::Response::Status::get_reason( undef, $status->[0], $status->[1] );

            $args{status_reason} = $status->[1];
        }
        else {
            $args{reason} = $status->[1] // Pcore::Util::Response::Status::get_reason( undef, $status->[0], $status->[2] );

            $args{status_reason} = $status->[2];
        }
    }
    else {
        $args{status} = $status;

        $args{reason} = Pcore::Util::Response::Status::get_reason( undef, $status, undef );
    }

    return bless \%args, 'Pcore::Util::Response::Status';
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Response

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
