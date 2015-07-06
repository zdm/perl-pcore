package Pcore::JS::ExtJS::Namespace;

use Pcore qw[-role];
use Pcore::JS::ExtJS::Request;
use Pcore::JS::ExtJS::Class;

with qw[Pcore::JS::Generator];

has app_name       => ( is => 'ro',  isa => SnakeCaseStr, required => 1 );
has ext_app_name   => ( is => 'ro',  isa => SnakeCaseStr, required => 1 );
has ext_class_ns   => ( is => 'ro',  isa => Str,          required => 1 );
has ext_class_name => ( is => 'rwp', isa => Str,          required => 1 );

has app_name_camel_case     => ( is => 'lazy', isa => Str, init_arg => undef );
has ext_app_name_camel_case => ( is => 'lazy', isa => Str, init_arg => undef );
has ext_app_ns              => ( is => 'lazy', isa => Str, init_arg => undef );

has ext_req => ( is => 'lazy', isa => InstanceOf ['Pcore::JS::ExtJS::Request'], clearer => 1 );

around _set_ext_class_name => sub {
    my $orig = shift;
    my $self = shift;

    $self->$orig(@_);

    $self->clear_ext_req;

    return;
};

no Pcore;

sub _build_app_name_camel_case {
    my $self = shift;

    return P->text->to_camel_case( $self->app_name, ucfirst => 1 );
}

sub _build_ext_app_name_camel_case {
    my $self = shift;

    return P->text->to_camel_case( $self->ext_app_name, ucfirst => 1 );
}

sub _build_ext_app_ns {
    my $self = shift;

    return $self->app_name_camel_case . $self->ext_app_name_camel_case;
}

sub _build_ext_req {
    my $self = shift;

    return Pcore::JS::ExtJS::Request->new(
        {   app_ns     => $self->ext_app_ns,
            class_ns   => $self->ext_class_ns,
            class_name => $self->ext_class_name,
        }
    );
}

sub ext_generate_class {
    my $self = shift;
    my %args = (
        readable => 0,
        @_,
    );

    my $method = 'ext_class_' . P->text->to_snake_case( $self->ext_req->class_name );

    return $self->_ext_generate_class( $self->$method, \%args ) if $self->can($method);

    return;
}

sub _ext_generate_class {
    my $self  = shift;
    my $class = shift;
    my $args  = shift;

    # add "extend" property
    $class->cfg->{extend} = $class->extend->class;

    # fill "requires" property
    if ( $self->ext_req->has_requires ) {
        my %requires;

        for my $req ( $self->ext_req->requires->@* ) {
            $req = $class->ext_req->get_descriptor($req) unless ref $req eq 'Pcore::JS::ExtJS::Class::Descriptor';

            $requires{ $req->class } = 1;
        }

        $class->cfg->{requires} = [ sort keys %requires ];
    }

    $class->_set__generated_as_class(1);

    return $class->js_generate( $class->js_call( 'Ext.define', $self->ext_class, $class ), readable => $args->{readable} );
}

sub ext_define {
    my $self   = shift;
    my $extend = shift;

    # parse arguments
    # supported arguments:
    # requires => ArrayRef, alias_ns => Str, {} - class config
    my %args;
    while ( my $arg = shift ) {
        if ( ref $arg eq 'HASH' ) {
            $args{cfg} = $arg;
        }
        else {
            $args{$arg} = shift;
        }
    }

    # add required attributes
    $args{ext_req} = $self->ext_req;
    $args{extend}  = $self->ext_req->get_descriptor($extend);

    return Pcore::JS::ExtJS::Class->new( \%args );
}

sub ext_class {
    my $self = shift;

    return $self->ext_req->class(@_);
}

sub ext_type {
    my $self = shift;

    return $self->ext_req->type(@_);
}

sub ext_api_class {
    my $self  = shift;
    my $class = shift;

    return $self->ext_class( $self->app_name_camel_case . q[Api.] . $class );
}

1;
__END__
=pod

=encoding utf8

=cut
