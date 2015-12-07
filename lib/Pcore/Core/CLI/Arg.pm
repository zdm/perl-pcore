package Pcore::Core::CLI::Arg;

use Pcore qw[-class];

with qw[Pcore::Core::CLI::Type];

has name => ( is => 'ro', isa => Str, required => 1 );

has isa => ( is => 'ro', isa => Maybe [ CodeRef | RegexpRef | ArrayRef | Enum [ keys $Pcore::Core::CLI::Type::TYPE->%* ] ] );

has min => ( is => 'ro', isa => PositiveOrZeroInt, default => 1 );    # 0 - option is not required
has max => ( is => 'lazy', isa => Maybe [PositiveInt] );              # undef - unlimited repeats

has type      => ( is => 'lazy', isa => Str, init_arg => undef );
has help_spec => ( is => 'lazy', isa => Str, init_arg => undef );

no Pcore;

sub BUILD ( $self, $args ) {
    my $name = $self->name;

    # max
    die qq[Argument "$name", "max" must be >= "min" ] if defined $self->max && $self->max < $self->min;

    return;
}

sub _build_max ($self) {
    return $self->min ? $self->min : 1;
}

sub _build_type ($self) {
    return uc $self->name =~ s/_/-/smgr;
}

sub _build_help_spec ($self) {
    my $spec;

    if ( $self->min == 0 ) {
        $spec = '[' . uc $self->type . ']';
    }
    else {
        $spec = uc $self->type;
    }

    $spec .= '...' if !defined $self->max || $self->max > 1;

    return $spec;
}

sub parse ( $self, $from, $to ) {
    if ( !$from->@* ) {
        if ( $self->min > 0 ) {
            return qq[required argument "@{[$self->type]}" is missed];
        }
        else {
            return;
        }
    }

    # check for minimum args num
    return qq[argument "@{[$self->type]}" must be repeated at least @{[$self->min]} time(s)] if $from->@* < $self->min;

    if ( defined $self->max ) {
        if ( $self->max == 1 ) {
            $to->{ $self->name } = shift $from->@*;
        }
        else {
            push $to->{ $self->name }->@*, splice $from->@*, 0, $self->max, ();
        }
    }
    else {
        push $to->{ $self->name }->@*, splice $from->@*, 0, scalar $from->@*, ();
    }

    # validate arg value type
    if ( $self->isa ) {
        if ( my $error_msg = $self->_validate_isa( $to->{ $self->name } ) ) {
            return qq[argument "@{[$self->type]}" $error_msg];
        }
    }

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 9                    │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::CLI::Arg

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
