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
        dist_name          => $self->namespace =~ s/::/-/smgr,                                                                    # Package-Name
        dist_path          => lc $self->namespace =~ s/::/-/smgr,                                                                 # package-name
        module_name        => $self->namespace,                                                                                   # Package::Name
        main_script        => 'main.pl',
        author             => $ENV->user_cfg->{'Pcore::Dist'}->{author},
        author_email       => $ENV->user_cfg->{'Pcore::Dist'}->{email},
        copyright_year     => P->date->now->year,
        copyright_holder   => $ENV->user_cfg->{'Pcore::Dist'}->{copyright_holder} || $ENV->user_cfg->{'Pcore::Dist'}->{author},
        license            => $ENV->user_cfg->{'Pcore::Dist'}->{license},
        bitbucket_username => $ENV->user_cfg->{'Pcore::API::Bitbucket'}->{username} // 'username',
        dockerhub_username => $ENV->user_cfg->{'Pcore::API::Dockerhub'}->{username} // 'username',
        cpan_distribution  => $self->cpan,
    };
}

sub run ($self) {
    if ( -e $self->target_path ) {
        $ERROR = 'Target path already exists';

        return;
    }

    my $files = Pcore::Util::File::Tree->new;

    $files->add_dir( $ENV->share->get_storage( 'pcore', 'Pcore' ) );

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
