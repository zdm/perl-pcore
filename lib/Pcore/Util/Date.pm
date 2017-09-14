package Pcore::Util::Date;

use Pcore;
use base qw[Time::Moment Pcore::Util::Date::Strptime];

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

# DURATION METHODS
sub duration_ms ( $self, $start, $end ) {
    my $delta = $start->delta_seconds($end);

    my $minutes = int $delta / 60;

    return $minutes, $delta - $minutes * 60;
}

sub duration_hm ( $self, $start, $end ) {
    my $delta = $start->delta_minutes($end);

    my $hours = int $delta / 60;

    return $hours, $delta - $hours * 60;
}

sub duration_hms ( $self, $start, $end ) {
    my $delta_sec = $start->delta_seconds($end);

    my $hours = int $delta_sec / 3_600;

    $delta_sec -= $hours * 3_600;

    my $minutes = int $delta_sec / 60;

    my $seconds = $delta_sec - $minutes * 60;

    return $hours, $minutes, $seconds;
}

sub duration_dhms ( $self, $start, $end ) {
    my $delta_sec = $start->delta_seconds($end);

    my $days = int $delta_sec / 86_400;

    $delta_sec -= $days * 86_400;

    my $hours = int $delta_sec / 3600;

    $delta_sec -= $hours * 3600;

    my $minutes = int $delta_sec / 60;

    my $seconds = $delta_sec - $minutes * 60;

    return $days, $hours, $minutes, $seconds;
}

sub duration_dhm ( $self, $start, $end ) {
    my $delta = $start->delta_minutes($end);

    my $days = int $delta / 1_440;

    $delta -= $days * 1_440;

    my $hours = int $delta / 60;

    return $days, $hours, $delta - $hours * 60;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Date

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
