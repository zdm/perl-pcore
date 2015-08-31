package Pcore::Util::Hash::Multivalue;

use Pcore;
use List::Util qw[pairkeys];    ## no critic qw[Modules::ProhibitEvilModules]
use Storable qw[dclone];

use overload                    #
  q[%{}] => sub {
    return $_[0]->[0];
  },
  fallback => undef;

sub new {
    my $self = shift;

    my $obj = bless [ {} ], $self;

    tie $obj->[0]->%*, 'Pcore::Util::Hash::Multivalue::_HASH';

    $obj->add(@_) if @_;

    return $obj;
}

sub clone ($self) {
    return Storable::dclone($self);
}

# return untied $hash->{$key} as ArrayRef
sub get ( $self, $key ) {
    if ( exists $self->[0]->{$key} ) {
        return tied( $self->[0]->%* )->[0]->{$key};
    }

    return;
}

# return untied HashRef
sub get_hash ($self) {
    return tied( $self->[0]->%* )->[0];
}

sub add {
    my $self = shift;
    my $args = $self->_parse_args(@_);

    my $hash = $self->get_hash;

    for ( my $i = 0; $i <= $args->$#*; $i += 2 ) {
        if ( !exists $hash->{ $args->[$i] } ) {
            $hash->{ $args->[$i] } = ref $args->[ $i + 1 ] eq 'ARRAY' ? $args->[ $i + 1 ] : [ $args->[ $i + 1 ] ];
        }
        else {
            push $hash->{ $args->[$i] }, ref $args->[ $i + 1 ] eq 'ARRAY' ? $args->[ $i + 1 ]->@* : $args->[ $i + 1 ];
        }
    }

    return $self;
}

sub set {    ## no critic qw[NamingConventions::ProhibitAmbiguousNames]
    my $self = shift;

    return $self->clear->add(@_);
}

sub replace {
    my $self = shift;
    my $args = $self->_parse_args(@_);

    return $self->remove( pairkeys $args->@* )->add($args);
}

sub remove {
    my $self = shift;

    delete $self->get_hash->@{@_};

    return $self;
}

sub clear ($self) {
    $self->get_hash->%* = ();

    return $self;
}

sub _parse_args {
    my $self = shift;

    return P->scalar->is_array( $_[0] ) ? $_[0] : P->scalar->is_hash( $_[0] ) ? [ $_[0]->%* ] : [@_];
}

sub to_uri ($self) {
    return P->data->to_uri( $self->get_hash );
}

sub to_array ($self) {
    my $array = [];

    my $hash = $self->get_hash;

    for my $key ( sort keys $hash ) {
        for my $val ( $hash->{$key}->@* ) {
            push $array, $key => $val;
        }
    }

    return $array;
}

sub TO_DUMP ( $self, $dumper, %args ) {
    return dump $self->get_hash;
}

package Pcore::Util::Hash::Multivalue::_HASH;

use Pcore;
use Tie::Hash;
use base qw[Tie::ExtraHash];

sub STORE {
    $_[0]->[0]->{ $_[1] } = ref $_[2] eq 'ARRAY' ? $_[2] : [ $_[2] ];

    return;
}

sub FETCH {
    return $_[0]->[0]->{ $_[1] }->[-1] if exists $_[0]->[0]->{ $_[1] };

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 18, 32, 40, 83, 91   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 18                   │ Miscellanea::ProhibitTies - Tied variable used                                                                 │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 49                   │ ControlStructures::ProhibitCStyleForLoops - C-style "for" loop used                                            │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Hash::Multivalue

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
