package Pcore::JS::Generator::Func;

use Pcore -class;

with qw[Pcore::JS::Generator::Base];

has func_name => ( is => 'ro', isa => Maybe [Str] );
has func_args => ( is => 'ro', isa => Maybe [ArrayRef] );
has func_body => ( is => 'ro', isa => Str, required => 1 );

no Pcore;

sub as_js {
    my $self = shift;

    my $js = 'function';
    $js .= q[ ] . $self->func_name if $self->func_name;
    $js .= q[(];
    $js .= join( q[,], $self->func_args->@* ) if $self->func_args;
    $js .= "){\n" . $self->func_body . "\n}";

    return $js;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    1 │ 19                   │ CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
