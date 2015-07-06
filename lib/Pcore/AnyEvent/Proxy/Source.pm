package Pcore::AnyEvent::Proxy::Source;

use Pcore qw[-role];
use Pcore::AnyEvent::Proxy;

requires qw[load];

has max_threads => ( is => 'ro', isa => PositiveOrZeroInt, default => 0 );

has _pool => ( is => 'ro', isa => InstanceOf ['Pcore::AnyEvent::Proxy::Pool'], required => 1, weak_ref => 1 );

has is_multiproxy => ( is => 'ro',  isa => Bool, default => 0, init_arg => undef );    # proxy can't be disabled / banned
has threads       => ( is => 'rwp', isa => Int,  default => 0, init_arg => undef );    # current threads (running request through this source)

around load => sub {
    my $orig      = shift;
    my $self      = shift;
    my $top_cv    = shift;
    my $temp_pool = shift;

    $top_cv->begin;

    my $cv = AnyEvent->condvar;

    my $proxies = [];

    $cv->begin(
        sub {
            my $addr_hash = {};

            for my $proxy_args ( $proxies->@* ) {
                if ( my $addr = delete $proxy_args->{addr} ) {
                    P->hash->merge( $proxy_args, Pcore::AnyEvent::Proxy->parse_uri($addr) );
                }

                my $id = $proxy_args->{host} . q[:] . $proxy_args->{port};

                $id .= q[@] . $proxy_args->{username} . q[:] . $proxy_args->{password} if $proxy_args->{username} && $proxy_args->{password};

                if ( !exists $addr_hash->{$id} ) {
                    $addr_hash->{$id} = $proxy_args;
                }
                else {
                    P->hash->merge( $addr_hash->{$id}, $proxy_args );
                }
            }

            # create and push proxy object
            for my $addr ( keys $addr_hash->%* ) {
                $addr_hash->{$addr}->{_source} = $self;

                push $temp_pool, Pcore::AnyEvent::Proxy->new( $addr_hash->{$addr} );
            }

            $top_cv->end;

            return;
        }
    );

    $self->$orig( $cv, $proxies );

    $cv->end;

    return;
};

no Pcore;

sub update_proxy_status {
    my $self  = shift;
    my $proxy = shift;

    $self->_pool->update_proxy_status($proxy);

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 49                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
