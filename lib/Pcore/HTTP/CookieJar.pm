package Pcore::HTTP::CookieJar;

use Pcore qw[-class];

has cookies => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

no Pcore;

sub parse_cookies ( $self, $url, $set_cookie_header ) {
  COOKIE: for ( $set_cookie_header->@* ) {
        my $cookie = {
            domain       => $url->host->name,
            cover_domain => 0,
            path         => q[/],
        };

        my ( $kvp, @attrs ) = split /;/sm;

        # trim
        $kvp =~ s/\A\s+//smo;
        $kvp =~ s/\s+\z//smo;

        next if $kvp eq q[];

        if ( ( my $idx = index $kvp, q[=] ) != -1 ) {
            $cookie->{name} = substr $kvp, 0, $idx;

            $cookie->{val} = substr $kvp, $idx + 1;
        }
        else {
            $cookie->{name} = $kvp;

            $cookie->{val} = q[];
        }

        for my $attr (@attrs) {

            # trim
            $attr =~ s/\A\s+//smo;
            $attr =~ s/\s+\z//smo;

            next if $attr eq q[];

            my ( $k, $v );

            if ( ( my $idx = index $attr, q[=] ) != -1 ) {
                $k = lc substr $attr, 0, $idx;

                $v = substr $attr, $idx + 1;
            }
            else {
                $k = lc $attr;

                $v = q[];
            }

            if ( $k eq 'domain' ) {

                # http://bayou.io/draft/cookie.domain.html
                #
                # origin domain - domain from the request
                # cover domain - domain from cookie attribute

                # if a cookie's origin domain is an IP, the cover domain must be null
                next COOKIE if $url->host->is_ip;

                # remove leading "." from cover domain
                $v =~ s/\A[.]+//smo;

                # the cover domain must not be a TLD
                # As far as cookie handling is concerned, every TLD is a public suffix, even if it's not listed.
                # For example, "test", "local", "my-fake-tld", etc. cannot be allowed as cover domains.
                next COOKIE if ( $v =~ tr/././ ) == 0;

                my $cover_domain = P->host( lc $v );

                # a cover domain must not be a IP address
                next COOKIE if $cover_domain->is_ip;

                # According to RFC_6265, if a cookie's cover domain is a public suffix:
                # - if the origin domain is the same domain, reset the cover domain to null, then accept the cookie
                # - otherwise, ignore the cookie entirely
                if ( $cover_domain->is_pub_suffix ) {
                    if ( $url->host->name eq $cover_domain->name ) {
                        next;    # accept cookie
                    }
                    else {
                        next COOKIE;    # ignore cookie
                    }
                }

                # the cover domain must not be a parent of a public suffix
                #
                # As far as cookie handling is concerned, parents of a public suffix are public suffixes too, even if they are not listed.
                # For example, amazonaws.com is not listed as a public suffix, yet it cannot be allowed as cover domain either,
                # because it is the parent of public suffix compute.amazonaws.com.
                next COOKIE if $cover_domain->is_pub_suffix_parent;

                # the cover domain must cover (be a substring) the origin domain
                next COOKIE if substr( $url->host->name, 0 - length $cover_domain->name ) ne $cover_domain->name;

                # accept coveer domain cookie
                $cookie->{domain} = $cover_domain->name;

                $cookie->{cover_domain} = 1;
            }
            elsif ( $k eq 'path' ) {
                $cookie->{path} = $v;
            }
            elsif ( $k eq 'expires' ) {

                # TODO
                $cookie->{expires} = $v;
            }
            elsif ( $k eq 'max-age' ) {

                # TODO
                $cookie->{max_age} = $v;
            }
            elsif ( $k eq 'httponly' ) {
                $cookie->{httponly} = 1;
            }
            elsif ( $k eq 'secure' ) {
                $cookie->{secure} = 1;
            }
        }

        $self->{cookies}->{ $cookie->{domain} }->{ $cookie->{path} }->{ $cookie->{name} } = $cookie;
    }

    say dump $self;

    return;
}

sub get_cookies ( $self, $headers, $url ) {

    # say dump \@_;

    # $headers->{COOKIE} = [ 111, 222 ];

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 9                    │ Subroutines::ProhibitExcessComplexity - Subroutine "parse_cookies" with high complexity score (23)             │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::CookieJar

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
