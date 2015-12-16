package Pcore::API::Map::Param::Fields;

use Pcore -class;

extends qw[Pcore::API::Map::Param];

has '+name' => ( is => 'ro', default => 'fields', init_arg => undef );
has '+null' => ( default => 1, init_arg => undef );
has '+isa_type' => ( init_arg => undef );

has field_set => ( is => 'ro', isa => HashRef [HashRef], default => sub { {} } );

# not exists - all allowed fields;
# undef - return all fields by default;
# Str - fields set name;
# ArrayRef[Str] - enum of fields names;
has '+default_value' => ( isa => Maybe [ Str | HashRef ], default => '__default_fields' );

has _default_fields => ( is => 'lazy', isa => HashRef, init_arg => undef );

around generate_api_map => sub {
    my $orig = shift;
    my $self = shift;

    my $api_map = $self->method->api_map;

    # check fields sets
    for my $field_set ( keys $self->field_set->%* ) {

        # validate and index fieldset fields
        for my $field_name ( keys $self->field_set->{$field_set}->%* ) {
            die qq[Field "$field_name", required by "$field_set" fields set of "fields" param, isn't defined] unless exists $api_map->fields->{$field_name};

            die qq[Field "$field_name" isn't writable] if !$api_map->fields->{$field_name}->is_writable;
        }
    }

    # check default value
    if ( defined $self->default_value ) {
        if ( ref $self->default_value eq 'HASH' ) {    # default value is a enum of fields
            for my $field_name ( keys $self->default_value->%* ) {
                die qq[Field "$field_name", required by "fields" param, isn't defined] unless exists $api_map->fields->{$field_name};

                die qq[Field "$field_name" isn't writable] if !$api_map->fields->{$field_name}->is_writable;
            }
        }
        else {
            if ( $self->default_value ne '__default_fields' ) {    # default value is a fields set name
                my $default_value = $self->default_value;

                die qq[Unknown fields set name "$default_value", used as param default value] unless exists $self->field_set->{$default_value};
            }
        }
    }

    return $self->$orig;
};

no Pcore;

sub BUILDARGS {
    my $self = shift;
    my $args = shift;

    # convert field_sets to hash
    if ( exists $args->{field_set} ) {
        for my $field_set ( keys $args->{field_set}->%* ) {
            my $fields = {};

            for my $field_name ( $args->{field_set}->{$field_set}->@* ) {
                $fields->{$field_name} = 1;
            }

            $args->{field_set}->{$field_set} = $fields;
        }
    }

    # convert default_value to hash
    if ( $args->{default_value} && ref $args->{default_value} eq 'ARRAY' ) {
        my $fields = {};

        for my $field_name ( $args->{default_value}->@* ) {
            $fields->{$field_name} = 1;
        }

        $args->{default_value} = $fields;
    }

    return $args;
}

sub _build__default_fields {
    my $self = shift;

    my $api_map_fields = $self->method->api_map->fields;

    return { map { $_ => 1 } grep { $api_map_fields->{$_}->write_field eq 'default' } keys $api_map_fields->%* };
}

sub reader {
    my $self             = shift;
    my $val              = shift;
    my $call             = shift;
    my $is_default_value = shift;

    my $api_map_fields = $self->method->api_map->fields;

    my $fields;

    if ( !defined $val->$* ) {
        return;    # skip param, all writable fields will be used
    }
    elsif ( ref $val->$* eq 'HASH' && !$is_default_value ) {
        return $call->exception(q[Invalid param value]);
    }
    elsif ( ref $val->$* eq 'ARRAY' ) {    # array of fields names
        $fields = $val->$*;

        my $writable_fields = {};

        # validate and index fields
        for my $field_name ( $fields->@* ) {
            return $call->exception(qq[Field "$field_name" isn't declared]) unless exists $api_map_fields->{$field_name};

            return $call->exception(qq[Field "$field_name" isn't writable]) if !$api_map_fields->{$field_name}->is_writable;

            $writable_fields->{$field_name} = 1;
        }

        $fields = $writable_fields;
    }
    elsif ( ref $val eq 'SCALAR' ) {
        if ( $val->$* eq '__default_fields' ) {    # default_field fields used
            $fields = $self->_default_fields;
        }
        else {                                     # named fields set
            return $call->exception( q[Unknown fields set "] . $val->$* . q["] ) unless exists $self->field_set->{ $val->$* };

            $fields = $self->field_set->{ $val->$* };
        }
    }
    else {
        return $call->exception(q[Invalid param value]);
    }

    return \$fields;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 28, 31, 41, 67, 97   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
