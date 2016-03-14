package Pcore::Util::Date;

use Pcore;
use base qw[Time::Moment];

# %a - The abbreviated weekday name ('Sun')
# %A - The  full  weekday  name ('Sunday')
# %b - The abbreviated month name ('Jan')
# %B - The  full  month  name ('January')
# %c - The preferred local date and time representation
# %d - Day of the month (01..31)
# %e - Day of the month without leading zeroes (1..31)
# %H - Hour of the day, 24-hour clock (00..23)
# %I - Hour of the day, 12-hour clock (01..12)
# %j - Day of the year (001..366)
# %k - Hour of the day, 24-hour clock w/o leading zeroes ( 0..23)
# %l - Hour of the day, 12-hour clock w/o leading zeroes ( 1..12)
# %m - Month of the year (01..12)
# %M - Minute of the hour (00..59)
# %p - Meridian indicator ('AM'  or  'PM')
# %P - Meridian indicator ('am'  or  'pm')
# %S - Second of the minute (00..60)
# %U - Week  number  of the current year, starting with the first Sunday as the first day of the first week (00..53)
# %W - Week  number  of the current year, starting with the first Monday as the first day of the first week (00..53)
# %w - Day of the week (Sunday is 0, 0..6)
# %x - Preferred representation for the date alone, no time
# %X - Preferred representation for the time alone, no date
# %y - Year without a century (00..99)
# %Y - Year with century
# %Z - Time zone name
# %z - +/- hhmm
# %% - Literal '%' character

sub from_strptime ( $self, $date, $format ) {
    state $zone_offset = do {
        require Time::Piece;
        require Time::Zone;

        my %zone_offset;

        @zone_offset{ keys %Time::Zone::dstZone } = values %Time::Zone::dstZone;
        @zone_offset{ keys %Time::Zone::Zone }    = values %Time::Zone::Zone;

        for ( keys %zone_offset ) {
            if ( $zone_offset{$_} < 0 ) {
                $zone_offset{$_} = [ $zone_offset{$_} / 60, sprintf '-%02s00', abs $zone_offset{$_} / 3600 ];
            }
            else {
                $zone_offset{$_} = [ $zone_offset{$_} / 60, sprintf '+%02s00', $zone_offset{$_} / 3600 ];
            }
        }

        \%zone_offset;
    };

    state $zone_re = do {
        my $re = '(' . join( q[|], sort { length $b cmp length $a } keys $zone_offset->%* ) . ')';

        qr/$re/smio;
    };

    local $SIG{__WARN__} = sub { };

    if ( ( my $idx = index $format, '%Z' ) != -1 && scalar $date =~ s/$zone_re/$zone_offset->{lc $1}->[1]/smio ) {
        substr $format, $idx, 2, '%z';

        my $zone = lc $1;

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
        return $self->new(
            year       => $http_date[0],
            month      => $http_date[1],
            day        => $http_date[2],
            hour       => $http_date[3],
            minute     => $http_date[4],
            second     => $http_date[5],
            nanosecond => 0,
            offset     => Time::Zone::tz_offset( $http_date[6] ) / 60,
        );
    }
    else {
        return;
    }
}

sub to_rfc_1123 ($self) {
    return $self->strftime('%a, %d %b %Y %H:%M:%S %z');
}

sub to_rfc_2616 ($self) {
    return $self->at_utc->strftime('%a, %d %b %Y %H:%M:%S GMT');
}

sub to_http_date ($self) {
    return $self->at_utc->strftime('%a, %d %b %Y %H:%M:%S GMT');
}

sub to_w3cdtf ($self) {
    return $self->strftime('%Y-%m-%dT%H:%M:%S%Z');
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 57                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 57                   │ BuiltinFunctions::ProhibitReverseSortBlock - Forbid $b before $a in sort blocks                                │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
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
