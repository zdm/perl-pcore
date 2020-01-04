package Pcore::App::Controller::Webpack;

use Pcore -role;

with qw[Pcore::App::Controller];

has app_dist => ( required => 1, init_arg => undef );

sub get_nginx_cfg ($self) {
    my $tmpl = <<'TXT';
    # webpack <: $location :> -> <: $root :>
    location <: $location :> {
        alias <: $root :>/;

        add_header Cache-Control "public, max-age=30672000";

        # index
        location =<: $location :> {
            add_header Cache-Control "public, private, must-revalidate, proxy-revalidate";
            try_files index.html =404;
        }
: if $location != '/' {

        location =<: $location :>/ {
            add_header Cache-Control "public, private, must-revalidate, proxy-revalidate";
            try_files index.html =404;
        }
: }

: if $location == '/' {
        location =/index.html {
: } else {
        location =<: $location :>/index.html {
: }
            add_header Cache-Control "public, private, must-revalidate, proxy-revalidate";
            try_files index.html =404;
        }
    }
TXT

    return P->tmpl->(
        \$tmpl,
        {   location => $self->{path},
            root     => $self->{app_dist},
        }
    )->$*;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::Controller::Webpack

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
