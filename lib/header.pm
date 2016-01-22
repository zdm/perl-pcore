package header;

# NOTE !!!WARNING!!! don't use indirect with strawberry perl
# https://rt.cpan.org/Public/Bug/Display.html?id=102321

use utf8;
use strict qw[refs subs vars];

no warnings;    ## no critic qw[TestingAndDebugging::ProhibitNoWarnings]
use warnings (
    'all',
    FATAL => qw[
      closed
      closure
      debugging
      digit
      glob
      inplace
      internal
      io
      layer
      malloc
      pack
      pipe
      portable
      printf
      prototype
      reserved
      semicolon
      taint
      threads
      unpack
      utf8
      ],
    NONFATAL => qw[
      exec
      newline
      unopened
      ]
);
no if $^V ge 'v5.18', warnings => 'experimental';
use if $^V lt 'v5.23', warnings => 'experimental::autoderef', FATAL => 'experimental::autoderef';

use if $^V ge 'v5.10', feature => ':all';
no  if $^V ge 'v5.16', feature => 'array_base';

use if $^V ge 'v5.10', mro => 'c3';
use if $^V ge 'v5.22', re  => 'strict';
no multidimensional;

BEGIN {
    eval <<"PERL";    ## no critic qw[BuiltinFunctions::ProhibitStringyEval ErrorHandling::RequireCheckingReturnValueOfEval]
        sub import {
            local \$^W;

            \${^WARNING_BITS} = "@{[ join( q[], map "\\x$_", unpack '(H2)*', ${^WARNING_BITS}) ]}";

            \$^H |= $^H;

            @^H{ qw[@{[ join q[ ], keys %^H ]}] } = (@{[ join q[, ], values %^H ]});

            return;
        }

        1;
PERL
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "common" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 1                    │ Modules::RequireVersionVar - No package-scoped "$VERSION" variable found                                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 1                    │ NamingConventions::Capitalization - Package "header" does not start with a upper case letter                   │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

header - re-exporting the set of standard perl pragmas

=head1 SYNOPSIS

    use header;

    # or re-export

    sub import {
        header->import( -caller => caller );
    }

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
