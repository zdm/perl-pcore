package Pcore::API::Map::Scanner;

use Pcore qw[-class];

has h_cache => ( is => 'ro', isa => InstanceOf ['Pcore::Core::H::Cache'],      required => 1, weak_ref => 1 );    # handles cache object
has backend => ( is => 'ro', isa => ConsumerOf ['Pcore::API::Backend::Local'], required => 1, weak_ref => 1 );
has app_ns => ( is => 'ro', isa => Str, required => 1 );

no Pcore;

sub scan {
    my $self = shift;

    warn q[Indexing API classes in "] . $self->app_ns . q[::API::" namespace];

    my $api_map = {};

    my $base_ns  = $self->app_ns . q[::];
    my $ns_class = qq[${base_ns}API::];
    my $ns_path  = $ns_class =~ s[::][/]smgr;

    # scan whole @INC directories
    for my $path ( sort grep { -d qq[$_/$ns_path] } @INC ) {
        P->file->finddepth(
            {   wanted => sub {
                    my $filename = $_;

                    if ( $filename =~ s/[.]pm\z//sm ) {    # is .pm file
                        my $class = $filename =~ s[\A$path/$ns_path][]smr =~ s[/][::]smgr;

                        warn qq[Found API class "$class"];

                        my $obj = $self->backend->get_api_obj( undef, $class );

                        if ( !$obj->does('Pcore::API::Class') ) {
                            croak(qq["$class" - API class should be an instance of "Pcore::API::Class"]);
                        }
                        else {
                            my $api_methods = $obj->_api_map->generate_api_map;

                            # skip class if hasn't methods configured
                            if ( !keys $api_methods->%* ) {
                                warn qq["$class" - has no API methods configured];

                                return;
                            }

                            # convert filename to action name
                            my $action = P->text->to_snake_case( $class, split => q[::], join => q[.] );

                            # store API action methods
                            $api_map->{$action} = $api_methods;
                        }
                    }
                },
                no_chdir => 1
            },
            qq[$path/$ns_path]
        );
    }

    return $api_map;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 42                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
