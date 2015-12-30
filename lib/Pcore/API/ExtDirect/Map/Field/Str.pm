package Pcore::API::Map::Field::Str;

use Pcore -class;

extends qw[Pcore::API::Map::Field];

has '+isa_type' => ( default => sub {Str} );
has blank => ( is => 'ro', isa => Bool, default => 0 );

around ext_model_field => sub {
    my $orig = shift;
    my $self = shift;

    my $field = $self->$orig(@_);

    $field->{type} = 'string';

    $field->{allowBlank} = $self->blank ? $TRUE : $FALSE;

    push $field->{validators}->@*, { type => 'presence' } if !$self->blank;

    return $field;
};

sub reader {
    my $self             = shift;
    my $val              = shift;
    my $call             = shift;
    my $is_default_value = shift;

    if ( !$self->blank && defined $val->$* && $val->$* eq q[] ) {
        return $call->exception(q[Field couldn't be an empty string]);
    }

    return $val;
}

sub writer {
    my $self = shift;
    my $val  = shift;

    if ( defined $val && defined $val->$* ) {
        $val->$* .= '';
    }

    return $val;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 43                   │ ValuesAndExpressions::ProhibitEmptyQuotes - Quotes used with a string containing no non-whitespace characters  │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
