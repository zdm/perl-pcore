package Pcore::API::Map::Field::Upload;

use Pcore -class;

extends qw[Pcore::API::Map::Field];

has '+null' => ( default => 0, init_arg => undef );
has '+isa_type'      => ( init_arg => undef );
has '+default_value' => ( init_arg => undef );

has '+persist' => ( init_arg => undef );
has '+upload'  => ( default  => 1 );

has '+write_field' => ( default => 'never', init_arg => undef );
has '+depends' => ( init_arg => undef );

has '+writer_method' => ( default => undef, init_arg => undef );

has multivalue => ( is => 'ro', isa => Bool, default => 0 );              # field value can be ArrayRef
has max_size => ( is => 'ro', isa => PositiveOrZeroInt, default => 0 );

no Pcore;

sub reader {
    my $self             = shift;
    my $val              = shift;
    my $call             = shift;
    my $is_default_value = shift;

    # check multivalue
    return $call->exception(q[Only single upload accepted]) if !$self->multivalue && $val->$*->@* > 1;

    # check upload size
    if ( $self->max_size ) {
        for my $upload ( $val->$*->@* ) {
            return $call->exception(q[Max. upload size exceeded]) if $upload->size > $self->max_size;
        }
    }

    return $val;
}

# EXT
sub ext_model_field {
    my $self = shift;

    return;
}

1;
__END__
=pod

=encoding utf8

=cut
