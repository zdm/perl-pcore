package Pcore::API::Map::Param;

use Pcore -class;
use Pcore::Util::Text qw[to_camel_case];

has name => ( is => 'ro', isa => StrMatch [qr/\A[[:lower:][:digit:]_]+\z/sm], required => 1 );
has alias_name => ( is => 'lazy', isa => Str, init_arg => undef );

has method => ( is => 'ro', isa => InstanceOf ['Pcore::API::Map::Method'], required => 1, weak_ref => 1 );

has critical => ( is => 'ro', isa => Bool, default => 0 );
has null          => ( is => 'lazy', isa       => Bool );
has isa_type      => ( is => 'ro',   isa       => InstanceOf ['Pcore::Core::Types::Type'], predicate => 1 );
has default_value => ( is => 'ro',   predicate => 1 );

has value => ( is => 'rwp', init_arg => undef );

has _reader_method => ( is => 'lazy', isa => Str, init_arg => undef );

no Pcore;

sub _build_alias_name {
    my $self = shift;

    return to_camel_case( $self->name );
}

sub _build_null {
    my $self = shift;

    return $self->has_default_value && !defined $self->default_value ? 1 : 0;
}

sub _build__reader_method {
    my $self = shift;

    my $method_name = 'read_param_' . $self->name;

    return $self->method->api_map->api_class->can($method_name) ? $method_name : q[];
}

# validate filter config
# called from method generate_api_map
# should die on errors
# retrun undef - for ignoring param
# return param name
sub generate_api_map {
    my $self = shift;

    die q[Default value can't be undef if null isn't alllowed] if $self->has_default_value && !defined $self->default_value && !$self->null;

    if ( $self->has_isa_type && $self->has_default_value && defined $self->default_value && !$self->isa_type->check( $self->default_value ) ) {
        die q[Param "] . $self->name . q[" default value doesn't pass isa type checking];
    }

    return $self->name;
}

sub read_param {
    my $self = shift;
    my $val  = shift;
    my $call = shift;

    my $is_default_value = 0;

    if ($val) {

        # check, for undef value
        return $call->exception(q[Param should be defined]) if !defined $val->$* && !$self->null;
    }
    else {
        # apply default value, if specified
        if ( $self->has_default_value ) {
            $val = \$self->default_value;

            $is_default_value = 1;
        }
        else {
            return;    # skip param
        }
    }

    $val = $self->reader( $val, $call, $is_default_value ) // return;

    # call external reader, if present
    if ( my $reader_method = $self->_reader_method ) {
        $val = $self->method->api_map->api_class->$reader_method( $self, $val, $call, $is_default_value ) // return;
    }

    # check isa_type
    if ( $self->has_isa_type && defined $val->$* ) {
        if ( my $error = $self->isa_type->validate( $val->$* ) ) {
            return $call->exception($error);
        }
    }

    $self->_set_value( $val->$* );

    return $self;
}

# template method, can be redefined in subclasses
sub reader {
    my $self             = shift;
    my $val              = shift;
    my $call             = shift;
    my $is_default_value = shift;

    return $val;
}

1;
__END__
=pod

=encoding utf8

=cut
