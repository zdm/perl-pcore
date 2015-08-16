package Pcore::Util::URI::Host;

use Pcore qw[-class];
use Net::IDN::Encode qw[];
use Regexp::Common qw[net];

use overload    #
  q[""] => sub {
    return $_[0]->to_string;
  },
  q[cmp] => sub {
    return $_[0]->to_string cmp $_[1];
  },
  fallback => undef;

has name               => ( is => 'ro',   required => 1 );
has name_ascii         => ( is => 'lazy', init_arg => undef );
has is_ip              => ( is => 'lazy', init_arg => undef );
has is_ipv4            => ( is => 'lazy', init_arg => undef );
has is_ipv6            => ( is => 'lazy', init_arg => undef );
has is_domain          => ( is => 'lazy', init_arg => undef );
has is_valid           => ( is => 'lazy', init_arg => undef );
has tld                => ( is => 'lazy', init_arg => undef );
has tld_ascii          => ( is => 'lazy', init_arg => undef );
has canon_domain       => ( is => 'lazy', init_arg => undef );    # host without www. prefix
has canon_domain_ascii => ( is => 'lazy', init_arg => undef );
has pub_suffix         => ( is => 'lazy', init_arg => undef );
has pub_suffix_ascii   => ( is => 'lazy', init_arg => undef );
has root_domain        => ( is => 'lazy', init_arg => undef );
has root_domain_ascii  => ( is => 'lazy', init_arg => undef );

no Pcore;

sub pub_suffixes {
    state $suffixes = do {
        my $path = P->res->get_local('effective_tld_names.dat');

        if ( !$path ) {
            P->ua->request(
                'https://publicsuffix.org/list/effective_tld_names.dat',
                chunk_size  => 0,
                on_progress => 0,
                blocking    => 1,
                on_finish   => sub ($res) {
                    $path = P->res->store_local( 'effective_tld_names.dat', $res->body ) if $res->status == 200;

                    return;
                }
            );
        }

        my $_suffixes = { map { $_ => 1 } grep { index( $_, q[//] ) == -1 } P->file->read_lines($path)->@* };
    };

    return $suffixes;
}

sub tlds {
    state $tlds = do {
        my $path = P->res->get_local('iana_tlds.dat');

        if ( !$path ) {
            P->ua->request(
                'https://data.iana.org/TLD/tlds-alpha-by-domain.txt',
                chunk_size  => 0,
                on_progress => 0,
                blocking    => 1,
                on_finish   => sub ($res) {
                    if ( $res->status == 200 ) {
                        $path = P->res->store_local( 'iana_tlds.dat', P->text->encode_utf8( \join $LF, map { lc Net::IDN::Encode::domain_to_unicode($_) } grep { $_ && !/\A\s*#/sm } split /\n/sm, $res->body->$* ) );
                    }

                    return;
                }
            );
        }

        my $_tlds = { map { $_ => 1 } P->file->read_lines($path)->@* };
    };

    return $tlds;
}

sub BUILDARGS ( $self, $args ) {

    # try to decode from punycode
    if ( index( $args->{name}, 'xn--' ) != -1 ) {
        $args->{name} = Net::IDN::Encode::domain_to_unicode( $args->{name} );
    }

    return $args;
}

sub to_string ($self) {
    return $self->name;
}

sub _build_name_ascii ($self) {
    return Net::IDN::Encode::domain_to_ascii( $self->name );
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
    if ( $self->name && $self->name =~ /\A$RE{net}{IPv4}\z/sm ) {
        return 1;
    }
    else {
        return 0;
    }
}

sub _build_is_ipv6 ($self) {
    if ( $self->name && $self->name =~ /\A$RE{net}{IPv6}\z/sm ) {
        return 1;
    }
    else {
        return 0;
    }
}

sub _build_is_domain ($self) {
    return $self->is_ip ? 0 : 1;
}

sub _build_is_valid ($self) {
    return 1 if $self->is_ip;

    if ( my $name = $self->name ) {
        return 0 if bytes::length($name) > 255;    # max length is 255 octets

        return 0 if $name =~ /[^[:alnum:]._\-]/sm; # allowed chars

        return 0 if $name !~ /\A[[:alnum:]]/sm;    # first character should be letter or digit

        return 0 if $name !~ /[[:alnum:]]\z/sm;    # last character should be letter or digit

        for ( split /[.]/sm, $name ) {
            return 0 if bytes::length($_) > 63;    # max. label length is 63 octets
        }

        return 1;
    }

    return 1;
}

sub _build_tld ($self) {
    if ( $self->is_ip ) {
        return q[];
    }
    else {
        return substr $self->name, rindex( $self->name, q[.] ) + 1;
    }
}

sub _build_tld_ascii ($self) {
    return Net::IDN::Encode::domain_to_ascii( $self->tld );
}

sub _build_canon_domain ($self) {
    return q[] if $self->is_ip;

    if ( my $name = $self->name ) {
        substr $name, 0, 4, q[] if index( $name, 'www.' ) == 0;

        return $name;
    }

    return q[];
}

sub _build_canon_domain_ascii ($self) {
    return Net::IDN::Encode::domain_to_ascii( $self->canon_domain );
}

sub _build_pub_suffix ($self) {
    if ( my $name = $self->canon_domain ) {
        return $name if exists pub_suffixes()->{$name};

        my @parts = split /[.]/sm, $name;

        return q[] if @parts == 1;

        while ( shift @parts ) {
            my $subhost = join q[.], @parts;

            return $subhost if exists pub_suffixes()->{$subhost};
        }
    }

    return q[];
}

sub _build_pub_suffix_ascii ($self) {
    return Net::IDN::Encode::domain_to_ascii( $self->pub_suffix );
}

sub _build_root_domain ($self) {
    if ( my $pub_suffix = $self->pub_suffix ) {
        if ( $self->canon_domain =~ /\A.*?([^.]+[.]$pub_suffix)\z/sm ) {
            return $1;
        }
    }

    return q[];
}

sub _build_root_domain_ascii ($self) {
    return Net::IDN::Encode::domain_to_ascii( $self->root_domain );
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::URI::Host

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
