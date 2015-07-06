package <: $module_name :> v0.1.0;

use Pcore qw[-class];

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    1 │ 7                    │ Documentation::RequirePackageMatchesPodName - Pod NAME on line 11 does not match the package declaration       │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

<: $module_name :>

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 SEE ALSO

=head1 AUTHOR

<: $author :> <<: $author_email :>>

=head1 CONTRIBUTORS

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) <: $copyright_year :> by <: $copyright_holder :>.

=cut
