package Pcore::Util::Result;

use Pcore -export, -const;
use Pcore::Util::Scalar qw[is_plain_arrayref is_plain_hashref];
use Pcore::Util::Result::Class;

our $EXPORT = [qw[res]];

our $STATUS_REASON;

const our $STATUS_CATEGORY => {
    '1xx' => 'Informational',
    '2xx' => 'Success',
    '3xx' => 'Redirection',
    '4xx' => 'Client Error',
    '5xx' => 'Server Error',
};

sub update ($cb = undef) {
    print 'updating status.yaml ... ';

    return P->http->get(
        'https://www.iana.org/assignments/http-status-codes/http-status-codes-1.csv',
        sub ($res) {
            if ($res) {
                my $data;

                for my $line ( split /\n\r?/sm, $res->{data}->$* ) {
                    my ( $status, $reason ) = split /,/sm, $line;

                    $data->{$status} = $reason if $status =~ /\A\d\d\d\z/sm;
                }

                local $YAML::XS::QuoteNumericStrings = 0;

                $ENV->{share}->write( 'Pcore', 'data/status.yaml', $data );

                $STATUS_REASON = $data;
            }

            say $res;

            $cb->($res) if $cb;

            return $res;
        }
    );
}

sub _load_data {
    $STATUS_REASON = $ENV->{share}->read_cfg( 'Pcore', 'data', 'status.yaml' );

    return;
}

# possible values for status:
# $status;
# [ $status, \%status_reason ]
# [ $status, $reason, \%status_reason ]
sub res ( $status, @args ) {
    my $self = @args % 2 ? { @args[ 1 .. $#args ], data => $args[0] } : {@args};

    $self = bless $self, 'Pcore::Util::Result::Class';

    if ( is_plain_arrayref $status ) {
        $self->{status} = $status->[0];

        if ( is_plain_hashref $status->[1] ) {
            $self->{reason} = resolve_reason( $status->[0], $status->[1] );
        }
        else {
            $self->{reason} = $status->[1] // resolve_reason( $status->[0], $status->[2] );
        }
    }
    else {
        $self->{status} = $status;

        $self->{reason} = resolve_reason($status);
    }

    return $self;
}

sub resolve_reason ( $status, $status_reason = undef ) {
    _load_data() if !defined $STATUS_REASON;

    if ( $status_reason && $status_reason->{$status} ) { return $status_reason->{$status} }
    elsif ( exists $STATUS_REASON->{$status} ) { return $STATUS_REASON->{$status} }
    elsif ( $status < 200 ) { return $STATUS_CATEGORY->{'1xx'} }
    elsif ( $status >= 200 && $status < 300 ) { return $STATUS_CATEGORY->{'2xx'} }
    elsif ( $status >= 300 && $status < 400 ) { return $STATUS_CATEGORY->{'3xx'} }
    elsif ( $status >= 400 && $status < 500 ) { return $STATUS_CATEGORY->{'4xx'} }
    else                                      { return $STATUS_CATEGORY->{'5xx'} }
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Result

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
