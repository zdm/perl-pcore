package Pcore::Util::Date;

use Pcore;
use HTTP::Date qw[];
use Time::Zone qw[];
use Time::Moment qw[];

no Pcore;

for my $sub (qw[new now now_utc from_epoch from_object from_string]) {
    no strict qw[refs];

    *{ 'Pcore::Util::Date::' . $sub } = sub {
        my $self = shift;

        return Time::Moment->$sub(@_);
    };
}

sub parse ( $self, $date ) {
    if ( my @http_date = HTTP::Date::parse_date($date) ) {
        return Time::Moment->new(
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

{
    no strict qw[refs];

    *{'Time::Moment::to_rfc_1123'} = sub {
        return $_[0]->strftime('%a, %d %b %Y %H:%M:%S %z');
    };

    *{'Time::Moment::to_rfc_2616'} = sub {
        return $_[0]->at_utc->strftime('%a, %d %b %Y %H:%M:%S GMT');
    };

    *{'Time::Moment::to_http_date'} = sub {
        return $_[0]->at_utc->strftime('%a, %d %b %Y %H:%M:%S GMT');
    };
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
