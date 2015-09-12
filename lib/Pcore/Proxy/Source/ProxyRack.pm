package Pcore::Proxy::ProxyRack;

use Pcore qw[-class];

with qw[Pcore::Proxy::Source];

has uri => ( is => 'ro', isa => Str, predicate => 1 );
has type => ( is => 'ro', isa => Enum [qw[ANY FASTEST TOP10]], default => 'FASTEST' );    # TOP10 - top 10% of all proxies

has '+load_timeout'       => ( default => 0 );
has '+max_threads_source' => ( isa     => Enum [ 50, 100, 200 ], default => 50 );
has '+is_multiproxy'      => ( default => 1 );

no Pcore;

sub load ( $self, $cb ) {
    my $proxies;

    if ( $self->uri ) {
        push $proxies->@*, $self->uri;
    }
    else {
        if ( $self->type eq 'ANY' ) {
            push $proxies->@*, '//37.58.52.41:2020';
        }
        elsif ( $self->type eq 'FASTEST' ) {
            push $proxies->@*, '//37.58.52.41:3030';
        }
        elsif ( $self->type eq 'TOP10' ) {
            push $proxies->@*, '//37.58.52.41:4040';
        }
    }

    $cb->($proxies);

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    1 │ 51                   │ Documentation::RequirePackageMatchesPodName - Pod NAME on line 55 does not match the package declaration       │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Proxy::Source::ProxyRack

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
