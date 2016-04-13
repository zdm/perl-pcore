package Pcore::Dist::Build::Create;

use Pcore -class;
use Pcore::Dist;
use Pcore::API::SCM;
use Pcore::API::Bitbucket;
use Pcore::Util::File::Tree;

has build => ( is => 'ro', isa => InstanceOf ['Pcore::Dist::Build'], required => 1 );

has path      => ( is => 'ro', isa => Str,  required => 1 );
has namespace => ( is => 'ro', isa => Str,  required => 1 );    # Dist::Name
has cpan      => ( is => 'ro', isa => Bool, default  => 0 );
has repo      => ( is => 'ro', isa => Bool, default  => 0 );    # create upstream repository

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
        scm_repo_owner     => $ENV->user_cfg->{'Pcore::API::Bitbucket'}->{repo_owner} // 'username',
        scm_repo_name      => lc $self->namespace =~ s/::/-/smgr,
        dockerhub_username => $ENV->user_cfg->{'Pcore::API::Dockerhub'}->{username} // 'username',
        cpan_distribution  => $self->cpan,
    };
}

sub run ($self) {
    if ( -e $self->target_path ) {
        $ERROR = 'Target path already exists';

        return;
    }

    # create upstream repo
    if ( $self->repo ) {
        my $bitbucket_api = Pcore::API::Bitbucket->new(
            {

                repo_owner   => $ENV->user_cfg->{'Pcore::API::Bitbucket'}->{'repo_owner'},
                repo_name    => lc $self->namespace =~ s[::][-]smgr,
                api_username => $ENV->user_cfg->{'Pcore::API::Bitbucket'}->{'api_username'},
                api_password => $ENV->user_cfg->{'Pcore::API::Bitbucket'}->{'api_password'},
            }
        );

        print 'Creating upstream repository ... ';

        my $res = $bitbucket_api->create_repository;

        if ( !$res->is_success ) {
            $ERROR = 'Error creating Bitbucket repository';

            say 'error';

            return;
        }

        say 'done';

        # clone upstream repo
        P->file->mkpath( $self->target_path );

        print 'Cloning upstream repository ... ';

        my $scm = Pcore::API::SCM->scm_clone( $self->target_path, "ssh://hg\@bitbucket.org/@{[$bitbucket_api->repo_owner]}/@{[$bitbucket_api->repo_name]}" );

        say 'done';
    }

    # copy files
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
