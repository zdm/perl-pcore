package Pcore::JS::ExtJS::Class::Descriptor;

use Pcore -class;

has descriptor => ( is => 'ro', isa => Str, required => 1 );

has app_ns     => ( is => 'ro', isa => Str, required => 1 );
has class_ns   => ( is => 'ro', isa => Str, required => 1 );
has class_name => ( is => 'ro', isa => Str, required => 1 );

has class => ( is => 'lazy', isa => Str, init_arg => undef );
has type  => ( is => 'lazy', isa => Str, init_arg => undef );
has ext_alias => ( is => 'lazy', isa => Maybe [Str], init_arg => undef );

has _parsed => ( is => 'lazy', isa => HashRef, init_arg => undef );

no Pcore;

our $EXT = P->cfg->load( $PROC->res->get('/data/extjs.perl') );

__PACKAGE__->register_classes( P->cfg->load( $PROC->res->get('/data/extjs_pcore.perl') ) );

sub register_classes {
    my $self = shift;
    my $types = ref $_[0] eq 'HASH' ? shift : {@_};

    for my $class ( keys %{$types} ) {
        $types->{$class} = [ $types->{$class} ] if ref $types->{$class} ne 'ARRAY';

        $EXT->{class_alias}->{$class} //= [];
        push $EXT->{class_alias}->{$class}, $types->{$class}->@*;

        for my $alias ( $types->{$class}->@* ) {
            die qq[Alias "$alias" already exists] if exists $EXT->{alias_class}->{$alias};

            $EXT->{alias_class}->{$alias} = $class;

            my ( $alias_ns, $alias_type ) = $alias =~ /\A(.+)[.](.+)\z/sm;
            $alias_ns //= $alias;
            $EXT->{alias_ns}->{$alias_ns} = 1;
        }
    }

    return;
}

sub _build__parsed {
    my $self = shift;

    my $parsed = {};

    if ( $self->descriptor =~ /[[:upper:]]/sm ) {
        $parsed->{is_class} = 1;

        if ( index( $self->descriptor, 'Ext.', 0 ) == 0 || index( $self->descriptor, 'Pcore.', 0 ) == 0 ) {
            $parsed->{is_standard_class} = 1;    # always full class descriptor
        }
        elsif ( $self->descriptor =~ /\A[[:upper:]]/sm && index( $self->descriptor, $self->app_ns . q[.], 0 ) != 0 && index( $self->descriptor, '.', 0 ) != -1 ) {
            $parsed->{is_external_class} = 1;    # always full class descriptor
        }
        else {
            $parsed->{is_app_class} = 1;

            if ( index( $self->descriptor, $self->app_ns . q[.], 0 ) != 0 ) {
                $parsed->{is_partial_app_class} = 1;

                ( $parsed->{class_ns}, $parsed->{class_name} ) = $self->descriptor =~ /\A(.+)[.](.+)\z/sm;

                $parsed->{class_name} //= $self->descriptor;
            }
        }
    }
    else {
        $parsed->{is_alias} = 1;

        ( $parsed->{alias_ns}, $parsed->{alias_type} ) = $self->descriptor =~ /\A(.+)[.](.+)\z/sm;

        if ( !$parsed->{alias_ns} ) {
            $parsed->{alias_ns}   = 'widget';
            $parsed->{alias_type} = $self->descriptor;
        }

        $parsed->{alias} = $parsed->{alias_ns} . q[.] . $parsed->{alias_type};
    }

    return $parsed;
}

sub _build_class {
    my $self = shift;

    my $class;

    if ( $self->_parsed->{is_class} ) {
        if ( $self->_parsed->{is_app_class} ) {
            if ( $self->_parsed->{is_partial_app_class} ) {    # partial class, generate full app class name
                if ( $self->_parsed->{class_ns} ) {
                    $class = $self->app_ns . q[.] . $self->_parsed->{class_ns} . q[.] . $self->_parsed->{class_name};
                }
                else {
                    $class = $self->app_ns . q[.];
                    $class .= $self->class_ns . q[.] if $self->class_ns;
                    $class .= $self->_parsed->{class_name};
                }
            }
            else {                                             # already full app class
                $class = $self->descriptor;
            }
        }
        elsif ( $self->_parsed->{is_external_class} ) {
            $class = $self->descriptor;
        }
        else {                                                 # full ext class, resolve alter class name
            $class = $EXT->{class_alter}->{ $self->descriptor } || $self->descriptor;
        }
    }
    else {
        $class = $EXT->{alias_class}->{ $self->_parsed->{alias} } if $EXT->{alias_class}->{ $self->_parsed->{alias} };
    }

    die q[Couldn't determine full class name for descriptor "] . $self->descriptor . q["] unless $class;

    return $class;
}

sub _build_type {
    my $self = shift;

    my $type;

    if ( $self->_parsed->{is_class} ) {
        my $class = $self->class;    # resolve alter class name

        if ( $self->_parsed->{is_standard_class} ) {    # Ext. or Pcore. class family, try to find registered alias
            if ( $EXT->{class_alias}->{$class} ) {
                ( my $alias_ns, $type ) = $EXT->{class_alias}->{$class}->[0] =~ /\A(.+)[.](.+)\z/sm;
            }
        }
        else {                                          # App. class or partial class
            $type = lc $class =~ s/[.]/-/smgr;
        }
    }
    else {
        $type = $self->_parsed->{alias_type} if exists $EXT->{alias_class}->{ $self->_parsed->{alias} };
    }

    die q[Couldn't determine alias type for descriptor "] . $self->descriptor . q["] unless $type;

    return $type;
}

sub _build_ext_alias {
    my $self = shift;

    my $class = $self->class;    # resolve alter class name

    if ( $EXT->{class_alias}->{$class} ) {
        return $EXT->{class_alias}->{$class}->[0];
    }
    else {
        return;
    }
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 58                   │ ValuesAndExpressions::ProhibitNoisyQuotes - Quotes used with a noisy string                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
