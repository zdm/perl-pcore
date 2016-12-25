package Pcore::Util::URI::Host;

use Pcore -class;
use Pcore::Util::Text qw[decode_utf8 encode_utf8];
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
has root_label           => ( is => 'lazy', init_arg => undef );
has root_label_utf8      => ( is => 'lazy', init_arg => undef );

our $TLD;
our $PUB_SUFFIX;

# NOTE host should be in UTF-8 or ASCII punycoded, UTF-8 encoded - is invalid value
around new => sub ( $orig, $self, $host ) {

    # removing double "."
    $host =~ s/[.]+/./smg if index( $host, q[..] ) != -1;

    # removing leading "."
    substr $host, 0, 1, q[] if substr( $host, 0, 1 ) eq q[.];

    # removing trailing "."
    substr $host, -1, 1, q[] if substr( $host, -1, 1 ) eq q[.];

    $host = domain_to_ascii($host) if utf8::is_utf8($host);

    return bless { name => lc $host }, __PACKAGE__;
};

sub update_all ( $self ) {

    # update TLD
    print 'updating tld.dat ... ';

    if ( my $res = P->http->get( 'https://data.iana.org/TLD/tlds-alpha-by-domain.txt', buf_size => 0, on_progress => 0 ) ) {
        my $domains;

        for my $domain_ascii ( map {lc} grep { $_ && !/\A\s*#/sm } split /\n/sm, $res->body->$* ) {
            $domains->{$domain_ascii} = domain_to_utf8($domain_ascii);
        }

        $ENV->share->store( '/data/tld.dat', \encode_utf8( join $LF, map {"$domains->{$_};$_"} sort { $domains->{$a} cmp $domains->{$b} } keys $domains->%* ), 'Pcore' );

        undef $TLD;

        say 'done';
    }
    else {
        say 'error';

        return 0;
    }

    # update pub. suffixes, should be updated after TLDs
    print 'updating pub_suffix.dat ... ';

    if ( my $res = P->http->get( 'https://publicsuffix.org/list/effective_tld_names.dat', buf_size => 0, on_progress => 0 ) ) {
        my $suffixes = {};

        decode_utf8 $res->body->$*;

        for my $domain_utf8 ( split /\n/sm, $res->body->$* ) {

            # remove spaces
            $domain_utf8 =~ s/\s//smg;

            # remove comments
            $domain_utf8 =~ s[//.*][]sm;

            # ignore empty lines
            next if $domain_utf8 eq q[];

            $suffixes->{ domain_to_ascii( lc $domain_utf8 ) } = lc $domain_utf8;
        }

        # add tlds
        $suffixes->@{ keys $self->tlds->%* } = values $self->tlds->%*;

        # add pub. suffix parent as pub. suffix
        for my $domain ( keys $suffixes->%* ) {
            my @labels = split /[.]/sm, $domain;

            # remove left label
            shift @labels;

            while (@labels) {
                my $label = shift @labels;

                # ignore "*" label
                next if $label eq q[*];

                my $parent_ascii = join q[.], $label, @labels;

                $suffixes->{$parent_ascii} = domain_to_utf8($parent_ascii) if !exists $suffixes->{$parent_ascii};
            }
        }

        $ENV->share->store( '/data/pub_suffix.dat', \encode_utf8( join $LF, map {"$suffixes->{$_};$_"} sort { $suffixes->{$a} cmp $suffixes->{$b} } keys $suffixes->%* ), 'Pcore' );

        undef $PUB_SUFFIX;

        say 'done';
    }
    else {
        say 'error';

        return 0;
    }

    return 1;
}

sub tlds ( $self ) {
    $TLD //= do {
        my $tlds;

        for my $rec ( split /\n/sm, P->file->read_text( $ENV->share->get('/data/tld.dat') )->$* ) {
            my ( $utf8, $ascii ) = split /;/sm, $rec;

            $tlds->{$ascii} = $utf8;
        }

        $tlds;
    };

    return $TLD;
}

sub pub_suffixes ( $self ) {
    $PUB_SUFFIX //= do {
        my $pub_suffix;

        for my $rec ( split /\n/sm, P->file->read_text( $ENV->share->get('/data/pub_suffix.dat') )->$* ) {
            my ( $utf8, $ascii ) = split /;/sm, $rec;

            $pub_suffix->{$ascii} = $utf8;
        }

        $pub_suffix;
    };

    return $PUB_SUFFIX;
}

sub to_string ($self) {
    return $self->{name};
}

sub _build_name_utf8 ($self) {
    return domain_to_utf8( $self->name );
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

    # host considered invalid if host is empty
    return 0;
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
    return domain_to_utf8( $self->tld );
}

sub _build_tld_is_valid ($self) {
    return exists $self->tlds->{ $self->tld } ? 1 : 0;
}

sub _build_canon ($self) {
    my $name = $self->name;

    substr $name, 0, 4, q[] if $name && index( $name, 'www.' ) == 0;

    return $name;
}

sub _build_canon_utf8 ($self) {
    return domain_to_utf8( $self->canon );
}

sub _build_is_pub_suffix ($self) {
    return 0 unless $self->is_domain;

    return length( $self->pub_suffix ) == length( $self->name ) ? 1 : 0;
}

# A public suffix is a set of DNS names or wildcards concatenated with dots.
# It represents the part of a domain name which is not under the control of the individual registrant.
# TODO wildcards like *.*.foo.bar should be supported
sub _build_pub_suffix ($self) {
    return q[] unless $self->is_domain;

    my $pub_suffixes = $self->pub_suffixes;

    my $pub_suffix;

    if ( my $name = $self->name ) {
        if ( exists $pub_suffixes->{$name} ) {
            $pub_suffix = $name;
        }
        else {
            my @labels = split /[.]/sm, $name;

            if ( @labels > 1 ) {
                while (@labels) {
                    my $first_label = shift @labels;

                    my $parent = join q[.], @labels;

                    if ( exists $pub_suffixes->{"*.$parent"} ) {
                        my $subdomain = "$first_label.$parent";

                        if ( !exists $pub_suffixes->{"!$subdomain"} ) {
                            $pub_suffix = $subdomain;

                            last;
                        }
                    }

                    if ( exists $pub_suffixes->{$parent} ) {
                        $pub_suffix = $parent;

                        last;
                    }

                    last if @labels == 1;
                }
            }
        }
    }

    return $pub_suffix // q[];
}

sub _build_pub_suffix_utf8 ($self) {
    return domain_to_utf8( $self->pub_suffix );
}

sub _build_is_root_domain ($self) {
    return 0 unless $self->is_domain;

    return length( $self->root_domain ) eq length( $self->name ) ? 1 : 0;
}

sub _build_root_domain ($self) {
    return q[] unless $self->is_domain;

    if ( my $pub_suffix = $self->pub_suffix ) {
        my $canon = $self->canon;

        return q[] if length $pub_suffix >= length $canon;

        my $root = substr $canon, 0, length($canon) - length($pub_suffix) - 1;

        return ( split /[.]/sm, $root )[-1] . ".$pub_suffix";
    }

    return q[];
}

sub _build_root_domain_utf8 ($self) {
    return domain_to_utf8( $self->root_domain );
}

sub _build_root_label ($self) {
    if ( my $root_domain = $self->root_domain ) {
        $root_domain =~ s/[.].+\z//sm;

        return $root_domain;
    }

    return q[];
}

sub _build_root_label_utf8 ($self) {
    if ( my $root_domain_utf8 = $self->root_domain_utf8 ) {
        $root_domain_utf8 =~ s/[.].+\z//sm;

        return $root_domain_utf8;
    }

    return q[];
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 306                  | ControlStructures::ProhibitDeepNests - Code structure is deeply nested                                         |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
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
