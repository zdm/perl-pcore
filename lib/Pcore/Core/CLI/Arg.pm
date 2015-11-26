package Pcore::Core::CLI::Arg;

use Pcore qw[-class];

with qw[Pcore::Core::CLI::Type];

has name => ( is => 'ro', isa => Str, required => 1 );

has isa => ( is => 'ro', isa => Maybe [ CodeRef | RegexpRef | ArrayRef | Enum [ keys $Pcore::Core::CLI::Type::TYPE->%* ] ] );

has min => ( is => 'ro', isa => PositiveOrZeroInt, default => 1 );    # 0 - option is not required
has max => ( is => 'lazy', isa => Maybe [PositiveInt] );              # undef - unlimited repeated

has type          => ( is => 'lazy', isa => Str,  init_arg => undef );
has is_repeatable => ( is => 'lazy', isa => Bool, init_arg => undef );
has is_required   => ( is => 'lazy', isa => Bool, init_arg => undef );
has is_last       => ( is => 'lazy', isa => Bool, init_arg => undef );
has help_spec     => ( is => 'lazy', isa => Str,  init_arg => undef );

no Pcore;

sub BUILD ( $self, $args ) {
    my $name = $self->name;

    # max
    die qq[Argument "$name", "max" must be >= "min" ] if $self->max && $self->max < $self->min;

    return;
}

sub _build_max ($self) {
    return $self->min ? $self->min : 1;
}

sub _build_type ($self) {
    return uc $self->name =~ s/_/-/smgr;
}

sub _build_is_repeatable ($self) {
    return !$self->max || $self->max > 1 ? 1 : 0;
}

sub _build_is_required ($self) {
    return $self->min ? 1 : 0;
}

sub _build_is_last ($self) {
    return 1 if !$self->is_required;

    return 1 if !$self->max;

    return 1 if $self->min != $self->max;

    return 0;
}

sub _build_help_spec ($self) {
    my $spec;

    if ( $self->is_required ) {
        $spec = uc $self->type;
    }
    else {
        $spec = '[' . uc $self->type . ']';
    }

    $spec .= '...' if $self->is_repeatable;

    return $spec;
}

sub parse ( $self, $from, $to ) {
    if ( !$from->@* ) {
        if ( $self->is_required ) {
            return qq[required argument "@{[$self->type]}" is missed];
        }
        else {
            return;
        }
    }

    if ( !$self->is_repeatable ) {
        $to->{ $self->name } = shift $from->@*;
    }
    else {
        return qq[argument "@{[$self->type]}" must be repeated at least @{[$self->min]} time(s)] if $from->@* < $self->min;

        if ( !$self->max ) {    # slurpy argument
            push $to->{ $self->name }->@*, splice $from->@*, 0, scalar $from->@*, ();

            return;
        }
        else {
            push $to->{ $self->name }->@*, splice $from->@*, 0, $self->max, ();
        }
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
