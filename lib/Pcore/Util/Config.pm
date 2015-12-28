package Pcore::Util::Config;

use Pcore;
use Pcore::Util::Text qw[encode_utf8];

sub load ( $cfg, @ ) {
    my %args = (
        ns   => undef,    # load cfg into specified namespace, only for perl configs
        from => undef,    # PERL, JSON, CBOR, YAML, XML, INI
        splice @_, 1,
    );

    my $from = delete $args{from};

    if ( !ref $cfg ) {
        if ( !-f $cfg ) {
            die qq[Config file "$cfg" wasn't found.];
        }

        if ( !$from ) {
            if ( my ($ext) = $cfg =~ /[.](json|cbor|yaml|yml|xml|ini)\z/sm ) {
                $from = $ext;

                $from = 'yaml' if $from eq 'yml';
            }
        }

        $cfg = P->file->read_bin($cfg);
    }
    else {
        encode_utf8 $cfg->$*;
    }

    $from //= 'PERL';

    return P->data->decode( $cfg, %args, from => uc $from );
}

sub store ( $path, $cfg, @ ) {
    my %args = (
        to => undef,    # PERL, JSON, CBOR, YAML, XML, INI
        splice @_, 2,
    );

    my $to = delete $args{to};

    if ( !$to ) {
        if ( my ($ext) = $path =~ /[.](json|cbor|yaml|yml|xml|ini)\z/sm ) {
            $to = $ext;

            $to = 'yaml' if $to eq 'yml';
        }
    }

    $to //= 'PERL';

    P->file->write_bin( $path, P->data->encode( $cfg, %args, to => uc $to ) );

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Config

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
