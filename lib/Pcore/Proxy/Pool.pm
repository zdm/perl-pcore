package Pcore::Proxy::Pool;

use Pcore qw[-class];

has load_timeout => ( is => 'ro', isa => PositiveOrZeroInt, default => 60 );    # 0 - don't re-load proxy sources
has _load_timer => ( is => 'ro', init_arg => undef );

has check_timeout => ( is => 'ro', isa => PositiveInt, default => 180 );        # timeout for re-check disabled proxies
has check_failure => ( is => 'ro', isa => PositiveInt, default => 3 );          # max. failed check attempts, after proxy will be removed from pool
has _check_timer => ( is => 'ro', init_arg => undef );

has ban_timeout => ( is => 'ro', isa => PositiveOrZeroInt, default => 60 );     # 0 - don't ban proxies

has _source => ( is => 'ro', isa => ArrayRef [ ConsumerOf ['Pcore::Proxy::Source'] ], default => sub { [] }, init_arg => undef );

has _on_proxy_activated => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

no Pcore;

sub BUILD ( $self, $args ) {
    if ( $args->{source} ) {
        my $min_source_load_timeout = 0;

        for my $source_args ( $args->{source}->@* ) {
            my %args = $source_args->%*;

            $args{pool} = $self;

            my $source = P->class->load( delete $args{class}, ns => 'Pcore::Proxy::Source' )->new( \%args );

            # set source load timeout = pool load timeout, if source timeout is not defined
            $source->{load_timeout} = $self->load_timeout if !defined $source->load_timeout;

            # define minimal source load interval, if source is reloadable
            if ( $source->load_timeout ) {
                if ( !$min_source_load_timeout ) {
                    $min_source_load_timeout = $source->load_timeout;
                }
                elsif ( $source->load_timeout < $min_source_load_timeout ) {
                    $min_source_load_timeout = $source->load_timeout;
                }
            }

            # add source to the pool
            push $self->_source, $source;
        }

        if ($min_source_load_timeout) {

            # create reload timer
            $self->{_load_timer} = AE::timer 0, $min_source_load_timeout, sub {
                $self->_on_load_timer;

                return;
            };
        }
        else {

            # all sources is not reloadable, run load once
            $self->_on_load_timer;
        }
    }

    # create check timer
    $self->{_check_timer} = AE::timer $self->check_timeout, $self->check_timeout, sub {
        $self->_on_check_timer;

        return;
    };

    return;
}

sub _on_load_timer ($self) {
    for my $source ( $self->_source->@* ) {
        $source->load;
    }

    return;
}

sub _on_check_timer ($self) {
    for my $source ( $self->_source->@* ) {
        $source->on_check_timer;
    }

    return;
}

# TODO
sub on_proxy_activated ( $self, $source, $proxy ) {
    return;
}

sub get_proxy ( $self, @ ) {
    my %args = (
        list => 'any',
        cb   => undef,
        wait => 0,
        @_[ 1 .. $#_ ]
    );

    my $proxy;

    my $source;

    my $weight;

    for ( $self->_source->@* ) {
        if ( my $w = $_->get_weight( $args{list} ) ) {
            $weight += $w;

            $source = $_ if rand($weight) < $w;
        }
    }

    $proxy = $source->get_proxy( $args{list} ) if $source;

    if ( $args{cb} ) {
        if ( !$proxy && $args{wait} ) {
            push $self->{_on_proxy_activated}->{ $args{list} }->@*, $args{cb};
        }
        else {
            $args{cb}->($proxy);
        }

        return;
    }
    else {
        return $proxy;
    }

    return $proxy;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 25                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 96                   │ CodeLayout::RequireTrailingCommas - List declaration without trailing comma                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Proxy::Pool

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
