package Pcore::Util::Date;

use Pcore;
use base qw[Time::Moment];

# %a - the abbreviated weekday name ('Sun')
# %A - the  full  weekday  name ('Sunday')
# %b - the abbreviated month name ('Jan')
# %B - the  full  month  name ('January')
# %c - the preferred local date and time representation
# %d - day of the month (01..31)
# %e - day of the month without leading zeroes (1..31)
# %H - hour of the day, 24-hour clock (00..23)
# %I - hour of the day, 12-hour clock (01..12)
# %j - day of the year (001..366)
# %k - hour of the day, 24-hour clock w/o leading zeroes ( 0..23)
# %l - hour of the day, 12-hour clock w/o leading zeroes ( 1..12)
# %m - month of the year (01..12)
# %M - minute of the hour (00..59)
# %p - meridian indicator ('AM'  or  'PM')
# %P - meridian indicator ('am'  or  'pm')
# %S - second of the minute (00..60)
# %U - week  number  of the current year, starting with the first Sunday as the first day of the first week (00..53)
# %W - week  number  of the current year, starting with the first Monday as the first day of the first week (00..53)
# %w - day of the week (Sunday is 0, 0..6)
# %x - preferred representation for the date alone, no time
# %X - preferred representation for the time alone, no date
# %y - year without a century (00..99)
# %Y - year with century
# %Z - time zone name
# %z - +/- hhmm
# %% - literal '%' character

sub from_strptime ( $self, $date, $format ) {
    state $zone_offset = do {
        require Time::Piece;
        require Time::Zone;

        my %zone_offset;

        @zone_offset{ keys %Time::Zone::dstZone } = values %Time::Zone::dstZone;
        @zone_offset{ keys %Time::Zone::Zone }    = values %Time::Zone::Zone;

        for ( keys %zone_offset ) {
            my $zone = uc;

            $zone_offset{$zone} = delete $zone_offset{$_};

            my $sec = abs $zone_offset{$zone};

            my $min = $sec % 3600;

            $sec -= $min;

            my $hour = $sec / 3600;

            $min = $min / 60;

            if ( $zone_offset{$zone} < 0 ) {
                $zone_offset{$zone} = [ $zone_offset{$zone} / 60, sprintf '-%02s%02s', $hour, $min ];
            }
            else {
                $zone_offset{$zone} = [ $zone_offset{$zone} / 60, sprintf '+%02s%02s', $hour, $min ];
            }
        }

        \%zone_offset;
    };

    state $zone_re = do {
        my $re = '(' . join( q[|], sort { length $b cmp length $a } keys $zone_offset->%* ) . ')';

        qr/$re/smio;
    };

    local $SIG{__WARN__} = sub { };

    if ( ( my $idx = index $format, '%Z' ) != -1 && scalar $date =~ s/$zone_re/$zone_offset->{uc $1}->[1]/smio ) {
        substr $format, $idx, 2, '%z';

        my $zone = uc $1;

        return $self->from_epoch( Time::Piece->strptime( $date, $format )->epoch )->with_offset_same_instant( $zone_offset->{$zone}->[0] );
    }
    else {
        return $self->from_epoch( Time::Piece->strptime( $date, $format )->epoch );
    }
}

sub parse ( $self, $date ) {
    state $init = do {
        require HTTP::Date;
        require Time::Zone;

        1;
    };

    if ( my @http_date = HTTP::Date::parse_date($date) ) {
        my %args = (    #
            year       => $http_date[0],
            month      => $http_date[1],
            day        => $http_date[2],
            hour       => $http_date[3],
            minute     => $http_date[4],
            second     => $http_date[5],
            nanosecond => 0,
        );

        if ( defined $http_date[6] ) {
            my $offset = Time::Zone::tz_offset( $http_date[6] );

            # invalid offset
            die qq[Invalid date offset "$http_date[6]"] if !defined $offset;

            $args{offset} = $offset / 60;
        }

        return $self->new(%args);
    }
    else {
        return;
    }
}

# %a, %d %b %Y %H:%M:%S %z
sub to_rfc_1123 ($self) {
    return $self->strftime('%a, %d %b %Y %H:%M:%S %z');
}

*to_http_date = \&to_rfc_2616;

# %a, %d %b %Y %H:%M:%S GMT
sub to_rfc_2616 ($self) {
    return $self->at_utc->strftime('%a, %d %b %Y %H:%M:%S GMT');
}

# %Y-%m-%dT%H:%M:%S%Z
sub to_w3cdtf ($self) {
    return $self->strftime('%Y-%m-%dT%H:%M:%S%Z');
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 71                   | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 71                   | BuiltinFunctions::ProhibitReverseSortBlock - Forbid $b before $a in sort blocks                                |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Date

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
