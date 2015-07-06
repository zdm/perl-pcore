package Pcore::HTTP::CookieJar;

use Pcore qw[-class];

# use Cookie::Baker;
# use Cookie::Baker::XS qw[];

no Pcore;

sub parse_cookies ( $self, $host, $headers ) {

    # my $cookies;
    #
    # for ( $headers->@* ) {
    #     # push $cookies->@*, Cookie::Baker::crush_cookie($_);
    #
    #     push $cookies->@*, CGI::Cookie::XS->parse($_);
    # }
    #
    # say dump $cookies;

    return;
}

sub get_cookies ( $self, $headers, $host ) {

    # say dump \@_;

    # $headers->{COOKIE} = [ 111, 222 ];

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::CookieJar

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
