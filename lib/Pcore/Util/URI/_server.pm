package Pcore::Util::URI::_server;    ## no critic qw[NamingConventions::Capitalization]

use Pcore qw[-class];

extends qw[Pcore::Util::URI];

no Pcore;

sub _new ( $self, $uri_args, $args ) {

    # https://tools.ietf.org/html/rfc3986#section-5
    # if URI has no scheme and base URI is specified - merge with base URI
    if ( $uri_args->{scheme} eq q[] && $args->{base} ) {

        # parse base URI
        $args->{base} = $self->_parse_uri_string( $args->{base} ) if !ref $args->{base};

        # https://tools.ietf.org/html/rfc3986#section-5.2.1
        # base URI MUST contain scheme
        if ( $args->{base}->{scheme} ne q[] ) {

            # https://tools.ietf.org/html/rfc3986#section-5.2.2
            # inherit scheme from base URI
            $uri_args->{scheme} = $args->{base}->{scheme};

            # inherit from the base URI only if has no own authority
            if ( !$uri_args->{has_authority} ) {

                # inherit authority
                $uri_args->{userinfo} = $args->{base}->{userinfo};
                $uri_args->{host}     = $args->{base}->{host};
                $uri_args->{port}     = $args->{base}->{port};

                if ( $uri_args->{path} eq q[] ) {
                    $uri_args->{path} = $args->{base}->{path};

                    $uri_args->{query} = $args->{base}->{query} if !$uri_args->{query};
                }
                else {

                    # path is relative, or no path
                    if ( substr( $uri_args->{path}, 0, 1 ) ne q[/] ) {
                        if ( $args->{base}->{path} ) {
                            my $slash_rindex = rindex $args->{base}->{path}, q[/];

                            # remove filename from base path
                            $args->{base}->{path} = substr( $args->{base}->{path}, 0, $slash_rindex ) . q[/] if $slash_rindex >= 0;

                            $uri_args->{path} = $args->{base}->{path} . q[/] . $uri_args->{path};
                        }
                    }
                }
            }
        }
    }

    $uri_args->{path} = q[/] if $uri_args->{has_authority} && $uri_args->{path} eq q[];

    return $self->SUPER::_new( $uri_args, $args );
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 9                    │ Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_new' declared but not used         │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 43                   │ ControlStructures::ProhibitDeepNests - Code structure is deeply nested                                         │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::URI::_server

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
