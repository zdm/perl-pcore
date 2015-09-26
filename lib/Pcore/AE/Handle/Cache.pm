package Pcore::AE::Handle::Cache;

use Pcore qw[-class];
use Pcore::AE::HAndle::Cache::Storage;
use Scalar::Util qw[refaddr];    ## no critic qw[Modules::ProhibitEvilModules]

has default_timeout => ( is => 'ro', isa => PositiveInt, default => 4 );

has handle     => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );
has connection => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

no Pcore;

sub clear ($self) {
    $self->{handle}->%* = ();

    $self->{connection}->%* = ();

    return;
}

sub store ( $self, $h, $timeout = undef ) {

    # do not cache destroyed handles
    return if $h->destroyed;

    return if !$h->{persistent_key};

    my $id = refaddr $h;

    # return if handle already cached
    return if exists $self->{handle}->{$id};

    # cache handle
    $self->{handle}->{$id} = $h;

    # cache handle connections
    for my $key ( $h->{persistent_key}->@* ) {
        $self->{connection}->{$key} //= Pcore::AE::Handle::Cache::Storage->new;

        $self->{connection}->{$key}->push($id);
    }

    my $destroy = sub ( $h, @ ) {
        delete $self->{handle}->{$id};

        for my $key ( $h->{persistent_key}->@* ) {
            $self->{connection}->{$key}->delete($id);

            delete $self->{connection}->{$key} if !$self->{connection}->{$key}->has_items;
        }

        # destroy handle
        $h->destroy;

        return;
    };

    # prepare handle for caching
    $self->on_error($destroy);
    $self->on_eof($destroy);
    $self->on_read($destroy);
    $self->on_timeout(undef);
    $self->timeout_reset;
    $self->timeout( $timeout || $self->default_timeout );

    return;
}

sub fetch ( $self, $key ) {
    return if !exists $self->{connection}->{$key};

    my $id = $self->{connection}->{$key}->shift;

    return if !$id;

    my $h = delete $self->{handle}->{$id};

    for ( $h->{persistent_key}->@* ) {
        $self->{connection}->{$_}->delete($id);

        delete $self->{connection}->{$_} if !$self->{connection}->{$_}->has_items;
    }

    $h->on_error(undef);
    $h->on_eof(undef);
    $h->on_read(undef);
    $h->timeout_reset;
    $h->timeout(0);

    return $h;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 15, 17               │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AE::Handle::Cache

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
