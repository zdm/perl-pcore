package Pcore::Util::Date;

use Pcore;
use base qw[Time::Moment];
use HTTP::Date qw[];
use Time::Zone qw[];

sub parse ( $self, $date ) {
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
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Date

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
