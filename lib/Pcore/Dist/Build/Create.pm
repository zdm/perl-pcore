package Pcore::Dist::Build::Create;

use Pcore -class;
use Pcore::Dist;
use Pcore::Util::File::Tree;

has build => ( is => 'ro', isa => InstanceOf ['Pcore::Dist::Build'], required => 1 );

has path      => ( is => 'ro', isa => Str,  required => 1 );
has namespace => ( is => 'ro', isa => Str,  required => 1 );    # Dist::Name
has cpan      => ( is => 'ro', isa => Bool, default  => 0 );

has target_path => ( is => 'lazy', isa => Str,     init_arg => undef );
has tmpl_params => ( is => 'lazy', isa => HashRef, init_arg => undef );

no Pcore;

our $ERROR;

sub BUILDARGS ( $self, $args ) {
    $args->{namespace} =~ s/-/::/smg if $args->{namespace};

    return $args;
}

sub _build_target_path ($self) {
    return P->path( $self->path, is_dir => 1 )->realpath->to_string . lc( $self->namespace =~ s[::][-]smgr );
}

sub _build_tmpl_params ($self) {
    return {
        dist_name          => $self->namespace =~ s/::/-/smgr,                                                            # Package-Name
        dist_path          => lc $self->namespace =~ s/::/-/smgr,                                                         # package-name
        module_name        => $self->namespace,                                                                           # Package::Name
        main_script        => 'main.pl',
        author             => $self->build->user_cfg->{_}->{author},
        author_email       => $self->build->user_cfg->{_}->{email},
        copyright_year     => P->date->now->year,
        copyright_holder   => $self->build->user_cfg->{_}->{copyright_holder} || $self->build->user_cfg->{_}->{author},
        license            => $self->build->user_cfg->{_}->{license},
        bitbucket_username => $self->build->user_cfg->{Bitbucket}->{username} // 'username',
        dockerhub_username => $self->build->user_cfg->{DockerHub}->{username} // 'username',
        cpan_distribution  => $self->cpan,
    };
}

sub run ($self) {
    if ( -e $self->target_path ) {
        $ERROR = 'Target path already exists';

        return;
    }

    if ( !$self->build->user_cfg ) {
        $ERROR = qq["@{[$self->build->user_cfg_path]}" was not found, run "pcore setup"];

        return;
    }

    my $files = Pcore::Util::File::Tree->new;

    $files->add_dir( $ENV->res->get_storage( 'pcore', 'pcore' ) );

    $files->move_file( 'lib/Module.pm', 'lib/' . $self->namespace =~ s[::][/]smgr . '.pm' );

    $files->render_tmpl( $self->tmpl_params );

    $files->write_to( $self->target_path );

    my $dist = Pcore::Dist->new( $self->target_path );

    # update dist after create
    $dist->build->update;

    return $dist;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::Build::Create

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
