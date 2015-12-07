package Pcore::Core::CLI::Opt;

# NOTE http://docopt.org/

use Pcore qw[-class];

with qw[Pcore::Core::CLI::Type];

has name => ( is => 'ro', isa => Str, required => 1 );
has short => ( is => 'lazy', isa => Maybe [ StrMatch [qr/\A[[:alpha:]]\z/sm] ] );    # undef - disable short option
has desc => ( is => 'ro', isa => Str );

has type => ( is => 'lazy', isa => Maybe [Str] );
has isa => ( is => 'ro', isa => Maybe [ CodeRef | RegexpRef | ArrayRef | Enum [ keys $Pcore::Core::CLI::Type::TYPE->%* ] ] );

has default     => ( is => 'ro', isa => Maybe [ Str | ArrayRef | HashRef ] );        # applied, when option is not exists
has default_val => ( is => 'ro', isa => Maybe [Str] );                               # applied, when option value is not defined

has min => ( is => 'ro', isa => PositiveOrZeroInt, default => 0 );                   # 0 - option is not required
has max => ( is => 'lazy', isa => Maybe [PositiveInt] );                             # undef - unlimited repeated

has negated => ( is => 'ro', isa => Bool, default => 0 );
has hash    => ( is => 'ro', isa => Bool, default => 0 );

has getopt_name   => ( is => 'lazy', isa => Str,  init_arg => undef );
has is_bool       => ( is => 'lazy', isa => Bool, init_arg => undef );
has is_repeatable => ( is => 'lazy', isa => Bool, init_arg => undef );
has is_required   => ( is => 'lazy', isa => Bool, init_arg => undef );
has getopt_spec   => ( is => 'lazy', isa => Str,  init_arg => undef );
has help_spec     => ( is => 'lazy', isa => Str,  init_arg => undef );

no Pcore;

sub BUILD ( $self, $args ) {
    my $name = $self->name;

    # max
    die qq[Option "$name", "max" must be >= "min" ] if $self->max && $self->max < $self->min;

    # default
    if ( defined $self->default ) {
        if ( $self->is_bool ) {
            die qq[Option "$name", "default" can be 1 or 0 for boolean option] if $self->default ne '0' && $self->default ne '1';
        }
        else {
            if ( $self->hash ) {
                die qq[Option "$name", "default" must be a HashRef] if ref $self->default ne 'HASH';
            }
            elsif ( $self->is_repeatable ) {
                die qq[Option "$name", "default" must be a ArrayRef] if ref $self->default ne 'ARRAY';
            }
        }
    }

    # default_val
    if ( defined $self->default_val ) {
        die qq[Option "$name", "default_val" can not be used for bool options] if $self->is_bool;

        die qq[Option "$name", "default_val" can not be used for hash options] if $self->hash;

        die qq[Option "$name", "default_val" can not be used for repeatable options] if $self->is_repeatable;
    }

    if ( $self->is_bool ) {
        die qq[Option "$name", "hash" is useless for boolean option] if $self->hash;

        die qq[Option "$name", "negated" is useless for "short" option] if defined $self->short && $self->negated;
    }
    else {
        die qq[Option "$name", "negated" is useless for not boolean option] if $self->negated;
    }

    return;
}

sub _build_max ($self) {
    return $self->min ? $self->min : 1;
}

sub _build_getopt_name ($self) {
    return $self->name =~ s/_/-/smgr;
}

sub _build_is_bool ($self) {
    return defined $self->isa ? 0 : 1;
}

sub _build_is_repeatable ($self) {
    return !$self->max || $self->max > 1 ? 1 : 0;
}

sub _build_is_required ($self) {
    return $self->min && !defined $self->default ? 1 : 0;
}

sub _build_short ($self) {
    return $self->negated ? undef : substr $self->name, 0, 1;
}

sub _build_type ($self) {
    if ( !$self->is_bool ) {
        my $ref = ref $self->isa;

        if ( !$ref ) {
            return uc $self->isa;
        }
        elsif ( $ref eq 'ARRAY' ) {
            return 'ENUM';
        }
        elsif ( $ref eq 'CODE' ) {
            return 'STR';
        }
        elsif ( $ref eq 'Regexp' ) {
            return 'STR';
        }
    }

    return;
}

sub _build_getopt_spec ($self) {
    my $spec = $self->getopt_name;

    $spec .= q[|] . $self->short if defined $self->short;

    if ( $self->is_bool ) {
        $spec .= q[!] if $self->negated;

        $spec .= q[+] if $self->is_repeatable;
    }
    else {
        if ( defined $self->default_val ) {
            $spec .= q[:s];
        }
        else {
            $spec .= q[=s];

            if ( $self->hash ) {
                $spec .= q[%];
            }
            elsif ( $self->is_repeatable ) {
                $spec .= q[@];
            }
        }
    }

    return $spec;
}

sub _build_help_spec ($self) {
    my $spec = $self->short ? q[-] . $self->short . q[ ] : q[ ] x 3;

    $spec .= q[--];

    $spec .= '[no[-]]' if $self->negated;

    $spec .= $self->getopt_name;

    if ( !$self->is_bool ) {
        my $type = uc $self->type;

        if ( $self->hash ) {
            $spec .= q[ key=] . $type;
        }
        else {
            if ( defined $self->default_val ) {
                $spec .= "=[$type]";
            }
            else {
                $spec .= " $type";
            }
        }
    }

    my @attrs;

    push @attrs, q[+] if $self->is_repeatable;

    push @attrs, q[!] if $self->is_required;

    $spec .= q[ ] . join q[], map {"[$_]"} @attrs if @attrs;

    return $spec;
}

sub validate ( $self, $opt ) {
    my $name = $self->name;

    # remap getopt name to name
    $opt->{$name} = delete $opt->{ $self->getopt_name } if exists $opt->{ $self->getopt_name };

    # check required option
    if ( !exists $opt->{$name} ) {
        return qq[option "$name" is required] if $self->is_required;

        # apply default value if defined
        $opt->{$name} = $self->default if defined $self->default;
    }
    elsif ( defined $self->default_val && $opt->{$name} eq q[] ) {

        # apply default_val if opt is exists. but value is not specified
        $opt->{$name} = $self->default_val;
    }

    # option is not exists and is not required
    return if !exists $opt->{$name};

    # validate min / max
    if ( $self->min || $self->max ) {
        my $count;

        if ( $self->is_bool ) {
            $count = $opt->{$name};
        }
        elsif ( !ref $opt->{$name} ) {
            $count = 1;
        }
        elsif ( ref $opt->{$name} eq 'ARRAY' ) {
            $count = scalar $opt->{$name}->@*;
        }
        elsif ( ref $opt->{$name} eq 'HASH' ) {
            $count = scalar keys $opt->{$name}->%*;
        }

        return qq[option "$name" must be specified at least @{[$self->min]} time(s)] if $self->min && $count < $self->min;

        return qq[option "$name" can be specified not more, than @{[$self->max]} time(s)] if $self->max && $count > $self->max;
    }

    # validate option value type
    if ( !$self->is_bool ) {
        if ( my $error_msg = $self->_validate_isa( $opt->{$name} ) ) {
            return qq[option "$name" $error_msg];
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
## │    3 │ 14, 222              │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 34                   │ Subroutines::ProhibitExcessComplexity - Subroutine "BUILD" with high complexity score (22)                     │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
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
