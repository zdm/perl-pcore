package Pcore::Core::CLI::Opt;

use Pcore qw[-class -const];

has name => ( is => 'ro', isa => Str, required => 1 );
has short => ( is => 'lazy', isa => Maybe [ StrMatch [qr/\A[[:alpha:]]\z/sm] ] );    # undef - disable short option
has desc  => ( is => 'ro',   isa => Str );
has type  => ( is => 'ro',   isa => Maybe [ Enum     [qw[s i o f -e -d -f]] ] );     # argument is required if type is present
has negated => ( is => 'ro', isa => Bool, default => 0 );                            # only for boolean options
has incr    => ( is => 'ro', isa => Bool, default => 0 );                            # only for boolean options
has desttype => ( is => 'ro', isa => Maybe [ Enum [qw[@ %]] ] );
has required => ( is => 'ro', isa => Bool, default => 0 );                           # if option is not exists - set default value or throw error
has default => ( is => 'ro', isa => Maybe [Str] );                                   # use, if option is exists and has no value
has min => ( is => 'ro', isa => PositiveOrZeroInt, default => 0 );
has max => ( is => 'ro', isa => PositiveOrZeroInt, default => 0 );
has type_desc => ( is => 'lazy', isa => Maybe [Str] );

has is_bool => ( is => 'lazy', isa => Bool, init_arg => undef );
has getopt_type => ( is => 'lazy', isa => Maybe [Str], init_arg => undef );
has getopt_spec => ( is => 'lazy', isa => Str, init_arg => undef );
has spec        => ( is => 'lazy', isa => Str, init_arg => undef );

no Pcore;

const our $GETOPT_TYPE_MAP => {
    s    => 's',
    i    => 'i',
    o    => 'o',
    f    => 'f',
    '-e' => 's',
    '-d' => 's',
    '-f' => 's',
};

const our $TYPE_DESC => {
    s    => 'STR',
    i    => 'INT',
    o    => 'EXTINT',
    f    => 'NUM',
    '-e' => 'PATH',
    '-d' => 'DIR',
    '-f' => 'FILE',
};

sub BUILD ( $self, $args ) {
    my $name = $self->name;

    if ( $self->is_bool ) {
        die qq[Default value for boolean option "$name" is invalid (can be 1 or 0)] if defined $self->default && $self->default ne '0' && $self->default ne '1';

        die qq[Short option "$name" can't be nagated] if defined $self->short && $self->negated;

        die qq[Boolean option "$name" can't have "desttype"] if defined $self->desttype;
    }
    else {
        die qq[Non-boolean option "$name" can't be negated] if $self->negated;

        die qq[Non-boolean option "$name" can't be incremental] if $self->incr;

        die qq[ARRAY or HASH option "$name" can't have default value] if defined $self->desttype && defined $self->default;
    }

    return;
}

sub _build_short ($self) {
    return $self->negated ? undef : substr $self->name, 0, 1;
}

sub _build_type_desc ($self) {
    return $self->type ? $TYPE_DESC->{ $self->type } : undef;
}

sub _build_is_bool ($self) {
    return defined $self->type ? 0 : 1;
}

sub _build_getopt_type ($self) {
    if ( !$self->is_bool ) {
        return $GETOPT_TYPE_MAP->{ $self->type };
    }
    else {
        return;
    }
}

sub _build_getopt_spec ($self) {
    my $spec = $self->name;

    $spec .= q[|] . $self->short if defined $self->short;

    if ( $self->is_bool ) {
        $spec .= q[!] if $self->negated;

        $spec .= q[+] if $self->incr;
    }
    else {
        $spec .= q[=] . $self->getopt_type;

        $spec .= $self->desttype if $self->desttype;

        if ( $self->min || $self->max ) {
            $spec .= q[{];

            $spec .= $self->min if $self->min;

            $spec .= q[,] . $self->max if $self->max;

            $spec .= q[}];
        }
    }

    return $spec;
}

sub _build_spec ($self) {
    my $spec = $self->short ? q[-] . $self->short . q[ ] : q[ ] x 3;

    $spec .= q[--];

    $spec .= '[no[-]]' if $self->negated;

    $spec .= $self->name;

    my @attrs;

    if ( $self->is_bool ) {
        push @attrs, q[+] if $self->incr;
    }
    else {
        my $type_desc = uc $self->type_desc;

        if ( $self->desttype ) {
            push @attrs, q[+];

            if ( $self->desttype eq q[@] ) {
                $spec .= qq[ $type_desc];
            }
            elsif ( $self->desttype eq q[%] ) {
                $spec .= qq[ key=$type_desc];
            }
        }
        else {
            $spec .= q[ ] . $type_desc;
        }
    }

    push @attrs, q[!] if $self->required && !defined $self->default;

    if (@attrs) {
        $spec .= q[ ] . join q[], map {qq[[$_]]} @attrs;
    }

    return $spec;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::CLI::Opt

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
