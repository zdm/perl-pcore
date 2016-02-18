package Pcore::Util::URI::Host;

use Pcore -class, -const;
use Pcore::Util::Text qw[encode_utf8];
use AnyEvent::Socket qw[];
use Pcore::Util::URI::Punycode qw[:ALL];

use overload    #
  q[""] => sub {
    return $_[0]->{name};
  },
  q[cmp] => sub {
    return !$_[2] ? $_[0]->{name} cmp $_[1] : $_[1] cmp $_[0]->{name};
  },
  fallback => undef;

has name                 => ( is => 'ro',   required => 1 );
has name_utf8            => ( is => 'lazy', init_arg => undef );
has is_ip                => ( is => 'lazy', init_arg => undef );
has is_ipv4              => ( is => 'lazy', init_arg => undef );
has is_ipv6              => ( is => 'lazy', init_arg => undef );
has is_domain            => ( is => 'lazy', init_arg => undef );
has is_valid             => ( is => 'lazy', init_arg => undef );
has is_tld               => ( is => 'lazy', init_arg => undef );    # domain is a known TLD
has tld                  => ( is => 'lazy', init_arg => undef );
has tld_utf8             => ( is => 'lazy', init_arg => undef );
has tld_is_valid         => ( is => 'lazy', init_arg => undef );
has canon                => ( is => 'lazy', init_arg => undef );    # host without www. prefix
has canon_utf8           => ( is => 'lazy', init_arg => undef );
has is_pub_suffix        => ( is => 'lazy', init_arg => undef );    # domain is a pub. suffix
has is_pub_suffix_parent => ( is => 'lazy', init_arg => undef );
has pub_suffix           => ( is => 'lazy', init_arg => undef );
has pub_suffix_utf8      => ( is => 'lazy', init_arg => undef );
has is_root_domain       => ( is => 'lazy', init_arg => undef );    # domain is a root domain
has root_domain          => ( is => 'lazy', init_arg => undef );
has root_domain_utf8     => ( is => 'lazy', init_arg => undef );

# NOTE host should be in UTF-8 or ASCII punycoded, UTF-8 encoded - is invalid value
around new => sub ( $orig, $self, $host ) {
    $host = to_punycode($host) if utf8::is_utf8($host);

    return bless { name => lc $host }, __PACKAGE__;
};

sub pub_suffixes ( $self, $force_download = 0 ) {
    state $suffixes = do {
        my $path = $ENV->share->get('/data/pub_suffix.dat');

        if ( !$path || $force_download ) {
            P->http->get(
                'https://publicsuffix.org/list/effective_tld_names.dat',
                buf_size    => 0,
                on_progress => 0,
                blocking    => 1,
                on_finish   => sub ($res) {
                    if ( $res->status == 200 ) {
                        my $_suffixes = {};

                        for my $domain ( split /\n/sm, $res->body->$* ) {

                            # ignore comments
                            next if $domain =~ m[//]smo;

                            # ignore empty lines
                            next if $domain =~ /\A\s*\z/smo;

                            $_suffixes->{$domain} = 1;
                        }

                        # add tlds
                        # TODO inherit force download tlds
                        for my $tld ( keys $self->tlds->%* ) {
                            utf8::encode($tld);

                            $_suffixes->{$tld} = 1;
                        }

                        # add domains, which is not known public suffixes, but is a public suffix parent
                        for my $domain ( keys $_suffixes->%* ) {
                            my @labels = split /[.]/sm, $domain;

                            shift @labels;

                            while (@labels) {
                                my $parent = join q[.], @labels;

                                $_suffixes->{ q[.] . $parent } = 1 if !exists $_suffixes->{$parent};

                                shift @labels;
                            }
                        }

                        $path = $ENV->share->store( \join( $LF, sort keys $_suffixes->%* ), '/data/pub_suffix.dat', 'Pcore' );
                    }

                    return;
                }
            );
        }

        my $_suffixes = { map { $_ => 1 } P->file->read_lines($path)->@* };
    };

    return $suffixes;
}

sub tlds ( $self, $force_download = 0 ) {
    state $tlds = do {
        my $path = $ENV->share->get('/data/tld.dat');

        if ( !$path || $force_download ) {
            P->http->get(
                'https://data.iana.org/TLD/tlds-alpha-by-domain.txt',
                buf_size    => 0,
                on_progress => 0,
                blocking    => 1,
                on_finish   => sub ($res) {
                    if ( $res->status == 200 ) {
                        $path = $ENV->share->store( \encode_utf8( join $LF, sort map { from_punycode(lc) } grep { $_ && !/\A\s*#/smo } split /\n/smo, $res->body->$* ), '/data/tld.dat', 'Pcore' );
                    }

                    return;
                }
            );
        }

        my $_tlds = { map { $_ => 1 } P->file->read_lines($path)->@* };
    };

    return $tlds;
}

sub to_string ($self) {
    return $self->{name};
}

sub _build_name_utf8 ($self) {
    return from_punycode( $self->name );
}

sub _build_is_ip ($self) {
    if ( $self->name && ( $self->is_ipv4 || $self->is_ipv6 ) ) {
        return 1;
    }
    else {
        return 0;
    }
}

sub _build_is_ipv4 ($self) {
    if ( $self->name && AnyEvent::Socket::parse_ipv4( $self->name ) ) {
        return 1;
    }
    else {
        return 0;
    }
}

sub _build_is_ipv6 ($self) {
    if ( $self->name && AnyEvent::Socket::parse_ipv6( $self->name ) ) {
        return 1;
    }
    else {
        return 0;
    }
}

sub _build_is_domain ($self) {
    return 0 if $self->name eq q[];

    return $self->is_ip ? 0 : 1;
}

sub _build_is_valid ($self) {
    return 1 if $self->is_ip;

    if ( my $name = $self->name ) {
        return 0 if bytes::length($name) > 255;    # max length is 255 octets

        return 0 if $name =~ /[^[:alnum:]._-]/sm;  # allowed chars

        return 0 if $name !~ /\A[[:alnum:]]/sm;    # first character should be letter or digit

        return 0 if $name !~ /[[:alnum:]]\z/sm;    # last character should be letter or digit

        for ( split /[.]/sm, $name ) {
            return 0 if bytes::length($_) > 63;    # max. label length is 63 octets
        }

        return 1;
    }

    return 1;
}

sub _build_is_tld ($self) {
    return 0 unless $self->is_domain;

    return $self->tld eq $self->name ? 1 : 0;
}

sub _build_tld ($self) {
    if ( $self->is_ip ) {
        return q[];
    }
    else {
        return substr $self->name, rindex( $self->name, q[.] ) + 1;
    }
}

sub _build_tld_utf8 ($self) {
    return from_punycode( $self->tld );
}

sub _build_tld_is_valid ($self) {
    return exists $self->tlds->{ $self->tld_utf8 } ? 1 : 0;
}

sub _build_canon ($self) {
    my $name = $self->name;

    substr $name, 0, 4, q[] if $name && index( $name, 'www.' ) == 0;

    return $name;
}

sub _build_canon_utf8 ($self) {
    return from_punycode( $self->canon );
}

sub _build_is_pub_suffix ($self) {
    return 0 unless $self->is_domain;

    return $self->pub_suffix eq $self->name ? 1 : 0;
}

sub _build_is_pub_suffix_parent ($self) {
    return 0 unless $self->is_domain;

    return exists $self->pub_suffixes->{ q[.] . $self->name_utf8 } ? 1 : 0;
}

sub _build_pub_suffix ($self) {
    return q[] unless $self->is_domain;

    my $pub_suffixes = $self->pub_suffixes;

    my $pub_suffix_utf8;

    if ( my $name = $self->name_utf8 ) {
        if ( exists $pub_suffixes->{$name} ) {
            $pub_suffix_utf8 = $name;
        }
        else {
            my @labels = split /[.]/sm, $name;

            if ( @labels > 1 ) {
                while (1) {
                    my $first_label = shift @labels;

                    my $parent = join q[.], @labels;

                    if ( exists $pub_suffixes->{$parent} ) {
                        $pub_suffix_utf8 = $parent;

                        last;
                    }
                    else {
                        if ( exists $pub_suffixes->{ q[*.] . $parent } ) {
                            my $subdomain = $first_label . q[.] . $parent;

                            if ( !exists $pub_suffixes->{ q[!] . $subdomain } ) {
                                $pub_suffix_utf8 = $subdomain;

                                last;
                            }
                        }
                    }

                    last if @labels <= 1;
                }
            }
        }
    }

    if ($pub_suffix_utf8) {
        $pub_suffix_utf8 = to_punycode($pub_suffix_utf8);

        return $pub_suffix_utf8;
    }
    else {
        return q[];
    }
}

sub _build_pub_suffix_utf8 ($self) {
    return from_punycode( $self->pub_suffix );
}

sub _build_is_root_domain ($self) {
    return 0 unless $self->is_domain;

    return $self->root_domain eq $self->name ? 1 : 0;
}

sub _build_root_domain ($self) {
    return q[] unless $self->is_domain;

    if ( my $pub_suffix = $self->pub_suffix ) {
        if ( $self->canon =~ /\A.*?([^.]+[.]$pub_suffix)\z/sm ) {
            return $1;
        }
    }

    return q[];
}

sub _build_root_domain_utf8 ($self) {
    return from_punycode( $self->root_domain );
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 72, 79, 93           │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 269, 272             │ ControlStructures::ProhibitDeepNests - Code structure is deeply nested                                         │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::URI::Host

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
