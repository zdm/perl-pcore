package Pcore::Util::URI::Web2;

use Pcore -role;

has _web2_data  => ( is => 'lazy', isa => Maybe [ArrayRef], init_arg => undef );
has web2_domain => ( is => 'lazy', isa => Maybe [Str],      init_arg => undef );
has web2_id     => ( is => 'lazy', isa => Maybe [Str],      init_arg => undef );
has is_web2 => ( is => 'lazy', isa => Bool, init_arg => undef );

our $WEB2_CFG = P->cfg->load( $ENV->share->get('/data/web2.perl') );

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

sub _build__web2_data ($self) {
    _web2_compile() if !$WEB2_HOST_RE;

    my $res;

    if ( $self->host->canon =~ $WEB2_HOST_RE ) {
        my $web2_domain = $1;

        my $web2_id = exists $WEB2_CFG->{$web2_domain} ? $web2_domain : $web2_domain =~ s/[.].+\z//smro;

        if ( $WEB2_CFG->{$web2_id}->{path} ) {

            # path-based web2 url must not contain subdomain and must have nont empty path
            $res = [ $web2_id, $web2_domain ] if $self->host->canon =~ /\A\Q$web2_domain\E\z/sm && $self->path =~ m[\A(/[^/]+)/?]smo;
        }
        elsif ( $self->host->canon =~ /\A[^.]+[.]\Q$web2_domain\E\z/sm ) {
            $res = [ $web2_id, $web2_domain ];
        }
    }

    return $res;
}

sub _build_web2_domain ($self) {
    if ( my $web2_data = $self->_web2_data ) {
        return $web2_data->[1];
    }
    else {
        return;
    }
}

sub _build_web2_id ($self) {
    if ( my $web2_data = $self->_web2_data ) {
        return $web2_data->[0];
    }
    else {
        return;
    }
}

sub _build_is_web2 ($self) {
    if ( my $web2_data = $self->_web2_data ) {
        return 1;
    }
    else {
        return 0;
    }
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

# NOTE http request must be performed with recursion enabled
sub is_web2_available ( $self, $http_res ) {
    return if !$self->is_web2;

    my $cfg = $WEB2_CFG->{ $self->web2_id };

    if ( $cfg->{status} && $http_res->status == $cfg->{status} ) { return 1 }

    if ( $cfg->{re} && $http_res->body->$* =~ $cfg->{re} ) { return 1 }

    return 0;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 17                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
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
