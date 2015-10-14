package Pcore::Util::URI::Web2;

use Pcore qw[-role];

has _is_web2_uri => ( is => 'lazy', isa => ArrayRef, init_arg => undef );
has web2_id      => ( is => 'lazy', isa => Str,      init_arg => undef );
has web2_domain  => ( is => 'lazy', isa => Str,      init_arg => undef );
has web2_canon   => ( is => 'lazy', isa => Str,      init_arg => undef );
has web2_url => ( is => 'lazy', init_arg => undef );

no Pcore;

our $WEB2_CFG = P->cfg->load( $P->{SHARE_DIR} . 'web2.perl' );

our $WEB2_HOST_RE;

sub _web2_compile {
    my @re;

    for my $host ( sort keys $WEB2_CFG->%* ) {
        if ( $host =~ /[.]/sm ) {
            push @re, quotemeta $host;
        }
        else {
            push @re, $host . '[.][[:alpha:].]{2,6}';
        }
    }

    my $re = join q[|], @re;

    $WEB2_HOST_RE = qr/($re)\z/smio;

    return;
}

sub web2_load_cfg ( $self, $cfg, $merge = 1 ) {
    if ($merge) {
        P->hash->merge( $WEB2_CFG, $cfg );
    }
    else {
        $WEB2_CFG = $cfg;
    }

    undef $WEB2_HOST_RE;

    return;
}

sub _build__is_web2_uri ($self) {
    my $res = [];

    _web2_compile() if !$WEB2_HOST_RE;

    if ( $self->host->canon =~ $WEB2_HOST_RE ) {
        my $web2_domain = $1;

        my $web2_id = $1;

        $web2_id =~ s/[.][^.]+\z//sm if !exists $WEB2_CFG->{$web2_id};

        if ( $WEB2_CFG->{$web2_id}->{path_subdomain} ) {
            if ( $self->host->canon =~ /\A\Q$web2_domain\E\z/sm && $self->path =~ m[\A(/[^/]+)/?]sm ) {
                $res = [ $web2_id, $web2_domain, $self->host->canon . $1 . q[/] ];
            }
        }
        elsif ( $self->host->canon =~ /\A[^.]+[.]\Q$web2_domain\E\z/sm ) {
            $res = [ $web2_id, $web2_domain, $self->host->canon ];
        }
    }

    return $res;
}

sub _build_web2_id ($self) {
    return $self->_is_web2_uri->[0] // q[];
}

sub _build_web2_domain ($self) {
    return $self->_is_web2_uri->[1] // q[];
}

sub _build_web2_canon ($self) {
    return $self->_is_web2_uri->[2] // q[];
}

sub _build_web2_url ($self) {
    if ( $self->web2_canon ) {
        return P->uri( ( $WEB2_CFG->{ $self->web2_id }->{scheme} // 'http' ) . q[://] . $self->web2_canon );
    }
    else {
        return q[];
    }
}

sub is_web2_available ( $self, $http_res ) {
    my $cfg = $WEB2_CFG->{ $self->web2_id };

    return 1 if ( $cfg->{status} ? $http_res->status == $cfg->{status} : 1 ) && ( $cfg->{host} ? $http_res->url->host eq $cfg->{host} : 1 ) && ( $cfg->{re} ? $http_res->body->$* =~ $cfg->{re} : 1 );

    return 0;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 20                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::URI::Web2

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
