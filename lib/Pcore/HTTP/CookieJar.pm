package Pcore::HTTP::CookieJar;

use Pcore -class;

has cookies => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

sub clear ($self) {
    $self->{cookies} = {};

    return;
}

sub parse_cookies ( $self, $url, $set_cookie_header ) {
  COOKIE: for ( $set_cookie_header->@* ) {
        my $cookie = {
            domain   => $url->host->name,
            path     => $url->path->to_string,
            expires  => 0,
            httponly => 0,
            secure   => 0,
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

                my $cover_domain = P->host( lc $v );

                # the cover domain must not be a TLD
                # As far as cookie handling is concerned, every TLD is a public suffix, even if it's not listed.
                # For example, "test", "local", "my-fake-tld", etc. cannot be allowed as cover domains.
                next COOKIE if $cover_domain->is_tld;

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
                $cookie->{domain} = q[.] . $cover_domain->name;
            }
            elsif ( $k eq 'path' ) {
                $cookie->{path} = $v;
            }
            elsif ( $k eq 'expires' ) {
                if ( !$cookie->{expires} ) {    # do not process expires attribute, if expires is already set by expires or max-age
                    if ( my $expires = P->date->parse($v) ) {
                        $cookie->{expires} = $expires->epoch;
                    }
                    else {
                        next COOKIE;            # ignore cookie, invalid expires value
                    }
                }
            }
            elsif ( $k eq 'max-age' ) {
                if ( $v =~ /\A\d+\z/sm ) {
                    $cookie->{expires} = time + $v;
                }
                else {
                    next COOKIE;                # ignore cookie, invalid max-age value
                }
            }
            elsif ( $k eq 'httponly' ) {
                $cookie->{httponly} = 1;
            }
            elsif ( $k eq 'secure' ) {
                $cookie->{secure} = 1;
            }
        }

        if ( $cookie->{expires} && $cookie->{expires} < time ) {
            delete $self->{cookies}->{ $cookie->{domain} }->{ $cookie->{path} }->{ $cookie->{name} };
        }
        else {
            $self->{cookies}->{ $cookie->{domain} }->{ $cookie->{path} }->{ $cookie->{name} } = $cookie;
        }
    }

    return;
}

sub get_cookies ( $self, $url ) {
    my @cookies;

    # origin cookie
    push @cookies, $self->_match_domain( $url->host->name, $url )->@*;

    # cover cookies
    # http://bayou.io/draft/cookie.domain.html#Coverage_Model
    if ( !$url->host->is_ip ) {
        my @labels = split /[.]/sm, $url->host->name;

        while ( @labels > 1 ) {
            my $domain = P->host( join q[.], @labels );

            last if $domain->is_pub_suffix;

            push @cookies, $self->_match_domain( q[.] . $domain->name, $url )->@*;

            shift @labels;
        }
    }

    return \@cookies;
}

sub _match_domain ( $self, $domain, $url ) {
    my @cookies;

    my $time = time;

    if ( exists $self->{cookies}->{$domain} ) {
        for my $cookie_path ( keys $self->{cookies}->{$domain}->%* ) {
            if ( $self->_match_path( $url->path, $cookie_path ) ) {
                for my $cookie ( values $self->{cookies}->{$domain}->{$cookie_path}->%* ) {
                    if ( $cookie->{expires} && $cookie->{expires} < $time ) {
                        delete $self->{cookies}->{$domain}->{$cookie_path}->{ $cookie->{name} };
                    }
                    else {
                        next if $cookie->{secure} && !$url->is_secure;

                        push @cookies, $cookie->{name} . q[=] . $cookie->{val};
                    }
                }
            }
        }
    }

    return \@cookies;
}

sub _match_path ( $self, $url_path, $cookie_path ) {
    return 1 if $cookie_path eq $url_path;

    return 1 if $cookie_path eq q[/];

    if ( $url_path =~ /\A\Q$cookie_path\E(.*)/sm ) {
        my $rest = $1;

        return 1 if substr( $cookie_path, -1, 1 ) eq q[/];

        return 1 if substr( $rest, 0, 1 ) eq q[/];
    }

    return 0;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 13                   │ Subroutines::ProhibitExcessComplexity - Subroutine "parse_cookies" with high complexity score (31)             │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 182, 184             │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
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
