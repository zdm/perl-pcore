package Pcore::API::Map::Field;

use Pcore -class;
use Pcore::Util::Text qw[to_camel_case];

has api_map => ( is => 'ro', isa => InstanceOf ['Pcore::API::Map'], required => 1, weak_ref => 1 );
has name => ( is => 'ro', isa => StrMatch [qr/\A[[:lower:][:digit:]_]+\z/sm], required => 1 );
has alias_name => ( is => 'lazy', isa => Str, init_arg => undef );

has persist => ( is => 'ro', isa => Maybe [ Enum [qw[rw rc ro]] ], default => undef );    # field physically stored in DB
has persist_rw => ( is => 'lazy', isa => Bool, init_arg => undef );                       # persist field, client can create / update this field
has persist_rc => ( is => 'lazy', isa => Bool, init_arg => undef );                       # persist field, client can create thid field
has persist_ro => ( is => 'lazy', isa => Bool, init_arg => undef );                       # persist field, readonly for client

has primary => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );              # field is a primary key
has upload  => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );

has null          => ( is => 'lazy', isa => Bool );
has isa_type      => ( is => 'ro',   isa => InstanceOf ['Pcore::Core::Types::Type'], predicate => 1 );
has default_value => ( is => 'ro',   isa => Maybe [Str], predicate => 1 );

# "fields" param related config
# on_request   - write field according to "fields" param value
# default || 1 - write field, if "fields" param is not defined
# always       - always write field
# never   || 0 - never write field by default, field can't be requested by "fields" param
has write_field => ( is => 'ro', isa => Enum [qw[on_request default always never]], default => 'on_request' );
has is_writable        => ( is => 'lazy', isa => Bool,     init_arg  => undef );
has is_always_writable => ( is => 'lazy', isa => Bool,     init_arg  => undef );
has depends            => ( is => 'ro',   isa => ArrayRef, predicate => 1 );       # array of fields, needed for this field calculation, applied for !persist fields only
has full_depends       => ( is => 'lazy', isa => ArrayRef, init_arg  => undef );
has persist_depends    => ( is => 'lazy', isa => ArrayRef, init_arg  => undef );

has filterable => ( is => 'lazy', isa => Bool );
has filter_isa_type => ( is => 'ro', isa => InstanceOf ['Pcore::Core::Types::Type'], predicate => 1 );

has sortable => ( is => 'lazy', isa => Bool );

has reader_method     => ( is => 'lazy', isa => Maybe [Str], init_arg => undef );
has can_reader_method => ( is => 'lazy', isa => Maybe [Str], init_arg => undef );
has writer_method     => ( is => 'lazy', isa => Maybe [Str], init_arg => undef );
has can_writer_method => ( is => 'lazy', isa => Maybe [Str], init_arg => undef );

has ext => ( is => 'ro', isa => HashRef, predicate => 1 );    # additional ext model field config

sub BUILDARGS {
    my $self = shift;
    my $args = shift;

    if ( exists $args->{write_field} ) {
        if ( $args->{write_field} eq '0' ) {
            $args->{write_field} = 'never';
        }
        elsif ( $args->{write_field} eq '1' ) {
            $args->{write_field} = 'default';
        }
    }

    return $args;
}

sub generate_api_map {
    my $self = shift;

    my $field_name = $self->name;

    die qq[Field "$field_name" default value can't be undef if null isn't alllowed] if $self->has_default_value && !defined $self->default_value && !$self->null;

    if ( $self->has_isa_type && $self->has_default_value && defined $self->default_value && !$self->isa_type->check( $self->default_value ) ) {
        die qq[Field "$field_name" default value doesn't pass isa type checking];
    }

    die qq[Filterable field "$field_name" should be persist] if $self->filterable && !$self->persist;

    die qq[Sortable field "$field_name" should be persist] if $self->sortable && !$self->persist;

    die qq[Persist read-only field "$field_name" must have default value or reader method] if $self->persist_ro && !$self->has_default_value && !$self->reader_method;

    die qq[Not persist field "$field_name" must have default value or writer method] if !$self->persist && $self->writer_method && !$self->can_writer_method && !$self->has_default_value;

    # check for cyclic dependencies
    $self->full_depends;

    return;
}

sub _build_alias_name {
    my $self = shift;

    return to_camel_case( $self->name );
}

sub _build_null {
    my $self = shift;

    return $self->has_default_value && !defined $self->default_value ? 1 : 0;
}

sub _build_persist_rw {
    my $self = shift;

    return defined $self->persist && $self->persist eq 'rw' ? 1 : 0;
}

sub _build_persist_rc {
    my $self = shift;

    return defined $self->persist && $self->persist eq 'rc' ? 1 : 0;
}

sub _build_persist_ro {
    my $self = shift;

    return defined $self->persist && $self->persist eq 'ro' ? 1 : 0;
}

sub _build_is_writable {
    my $self = shift;

    return $self->write_field eq 'never' ? 0 : 1;
}

sub _build_is_always_writable {
    my $self = shift;

    return $self->write_field eq 'always' ? 1 : 0;
}

sub _build_filterable {
    my $self = shift;

    return $self->persist ? 1 : 0;
}

sub _build_sortable {
    my $self = shift;

    return $self->persist ? 1 : 0;
}

sub _build_full_depends {
    my $self = shift;

    my $depends = {};

    # field can't be dependent from itself
    my $process_depends = sub {
        my $field = shift;

        if ( $field->has_depends ) {
            for my $field_name ( $field->depends->@* ) {

                # dependency field not declared
                die qq[Can't resolve field dependency "$field_name" for field "] . $self->name . q["] unless exists $self->api_map->fields->{$field_name};

                # cyclic dependency found
                die q[Cyclic dependency detected. Field "] . $self->name . q[" depends from themself] if $field_name eq $self->name;

                $depends->{$field_name} = 1;

                __SUB__->( $self->api_map->fields->{$field_name} );
            }
        }

        return;
    };

    $process_depends->($self);

    return [ keys $depends->%* ];
}

sub _build_persist_depends {
    my $self = shift;

    return [ grep { $self->api_map->fields->{$_}->persist } $self->full_depends->@* ];
}

sub _build_reader_method {
    my $self = shift;

    return 'read_field_' . $self->name;
}

sub _build_can_reader_method {
    my $self = shift;

    return $self->reader_method && $self->api_map->api_class->can( $self->reader_method ) ? $self->reader_method : undef;
}

sub _build_writer_method {
    my $self = shift;

    return 'write_field_' . $self->name;
}

sub _build_can_writer_method {
    my $self = shift;

    return $self->writer_method && $self->api_map->api_class->can( $self->writer_method ) ? $self->writer_method : undef;
}

sub _read_field {
    my $self = shift;
    my $val  = shift;
    my $call = shift;

    my $is_default_value = 0;

    if ($val) {    # field is exists in input data

        # check, for undef value
        return $call->exception(q[Field should be defined]) if !$self->null && !defined $val->$*;
    }
    else {         # field wasn't found in input data

        # apply default value, if specified
        if ( $self->has_default_value ) {
            $val = \$self->default_value;

            $is_default_value = 1;
        }
        else {
            return;    # skip field if not present in input data and hasn't default value
        }
    }

    # call internal reader
    $val = $self->reader( $val, $call, $is_default_value ) // return;

    # call external reader, if present
    if ( my $reader_method = $self->can_reader_method ) {
        $val = $self->api_map->api_class->$reader_method( $self, $val, $call, $is_default_value ) // return;
    }

    # check isa_type
    if ( $self->has_isa_type && defined $val->$* ) {
        if ( my $error = $self->isa_type->validate( $val->$* ) ) {
            return $call->exception($error);
        }
    }

    return $val;
}

# template method, can be redefined in subclasses
# should retrun undef - to ignore field or reference to value
sub reader {
    my $self             = shift;
    my $val              = shift;
    my $call             = shift;
    my $is_default_value = shift;

    return $val;
}

# should return:
# undef - don't write field
# -1    - don't write row
# REF   - field value
sub _write_field {
    my $self = shift;
    my $val  = shift;
    my $rec  = shift;

    # call external writer, if present
    if ( my $writer_method = $self->can_writer_method ) {
        $val = $self->api_map->api_class->$writer_method( $val, $rec );
    }

    # call internal writer
    $val = $self->writer($val);

    return $val;
}

# template method, can be redefined in subclasses
sub writer {
    my $self = shift;
    my $val  = shift;

    return $val;
}

# EXT
sub ext_model_field {
    my $self = shift;

    my $field = {
        name    => $self->alias_name,
        persist => $self->persist_rw || $self->persist_rc ? $TRUE : $FALSE,
        allowNull => $self->null ? $TRUE : $FALSE,
        mapping => $self->name,
    };

    $field->{defaultValue} = $self->default_value if $self->has_default_value;

    P->hash->merge( $field, $self->ext ) if $self->has_ext;

    return $field;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 170                  │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │                      │ Subroutines::ProhibitUnusedPrivateSubroutines                                                                  │
## │      │ 203                  │ * Private subroutine/method '_read_field' declared but not used                                                │
## │      │ 261                  │ * Private subroutine/method '_write_field' declared but not used                                               │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
