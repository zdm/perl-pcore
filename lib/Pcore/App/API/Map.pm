package Pcore::App::API::Map;

use Pcore -class;

has app => ( is => 'ro', isa => ConsumerOf ['Pcore::App'], required => 1 );

sub BUILD ( $self, $args ) {

    #     my $map = {};
    #
    #     my $ns_path = ref($self) =~ s[::][/]smgr;
    #
    #     my $controllers = {};
    #
    #     # scan namespace, find and preload controllers
    #     for my $path ( grep { !ref } @INC ) {
    #         if ( -d "$path/$ns_path" ) {
    #             my $guard = P->file->chdir("$path/$ns_path");
    #
    #             P->file->find(
    #                 "$path/$ns_path",
    #                 abs => 0,
    #                 dir => 0,
    #                 sub ($path) {
    #                     if ( $path->suffix eq 'pm' ) {
    #                         my $route = $path->dirname . $path->filename_base;
    #
    #                         my $class = "$ns_path/$route" =~ s[/][::]smgr;
    #
    #                         # TODO conver to perl_class_snake_case
    #                         $controllers->{$class} = P->text->to_snake_case( $route, delim => '-', split => '/', join => '/' );
    #                     }
    #
    #                     return;
    #                 }
    #             );
    #         }
    #     }
    #
    #     for my $class_name ( sort keys $controllers->%* ) {
    #         P->class->load($class_name);
    #
    #         my $class_path = $controllers->{$class_name};
    #
    #         if ( !$class_name->does('Pcore::App::API::Role') ) {
    #             delete $controllers->{$class_name};
    #
    #             say qq["$class_name" is not a consumer of "Pcore::App::API::Role"];
    #
    #             next;
    #         }
    #
    #         my $version;
    #
    #         if ( $class_path =~ s[\Av(\d+)/][]sm ) {
    #             $version = $1;
    #         }
    #         else {
    #             say qq[Can not determine API version "$class_name"];
    #
    #             next;
    #         }
    #
    #         my $obj = bless { app => $self->app }, $class_name;
    #
    #         my $obj_map = $obj->map;
    #
    #         for my $method ( keys $obj_map->%* ) {
    #             my $method_id = qq[/v$version/$class_path/$method];
    #
    #             $map->{$method_id} = {
    #                 $obj_map->{$method}->%*,
    #                 id          => $method_id,
    #                 version     => "v$version",
    #                 class_name  => $class_name,
    #                 class_path  => $class_path,
    #                 method_name => $method,
    #             };
    #
    #             # validate api method configuration
    #             die qq[API method "$method_id" requires description] if !$map->{$method_id}->{desc};
    #         }
    #     }
    #
    #     say dump $map;
    #     exit;

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Map

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
