package Pcore::Dist::Build::Create;

use Pcore -class;
use Pcore::Dist;
use Pcore::API::SCM;
use Pcore::API::Bitbucket;
use Pcore::Util::File::Tree;

has build => ( is => 'ro', isa => InstanceOf ['Pcore::Dist::Build'], required => 1 );

has base_path => ( is => 'ro', isa => Str,  required => 1 );
has namespace => ( is => 'ro', isa => Str,  required => 1 );    # Dist::Name
has cpan      => ( is => 'ro', isa => Bool, default  => 0 );
has upstream => ( is => 'ro', isa => Enum [qw[bitbucket github]], default => 'bitbucket' );    # create upstream repository
has upstream_namespace => ( is => 'ro', isa => Str );                                          # upstream repository namespace
has private            => ( is => 'ro', isa => Bool, default => 0 );
has scm                => ( is => 'ro', isa => Enum [qw[hg git hg-git]], default => 'hg' );    # SCM for upstream repository

has upstream_repo_id => ( is => 'ro',   isa => Str,     init_arg => undef );
has target_path      => ( is => 'lazy', isa => Str,     init_arg => undef );
has tmpl_params      => ( is => 'lazy', isa => HashRef, init_arg => undef );

our $ERROR;

sub BUILDARGS ( $self, $args ) {
    $args->{namespace} =~ s/-/::/smg if $args->{namespace};

    return $args;
}

sub _build_target_path ($self) {
    return P->path( $self->base_path, is_dir => 1 )->realpath->to_string . lc( $self->namespace =~ s[::][-]smgr );
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
        dockerhub_username => $ENV->user_cfg->{'Pcore::API::Dockerhub'}->{username} // 'username',
        cpan_distribution  => $self->cpan,
    };
}

sub run ($self) {
    if ( -e $self->target_path ) {
        $ERROR = 'Target path already exists';

        return;
    }

    if ( $self->upstream eq 'github' ) {

        # GitHub support only git SCM
        $self->{scm} = 'git';

        $ERROR = 'GitHub currently is not supported';

        return;
    }

    if ( $self->scm eq 'git' ) {
        $ERROR = 'Git SCM currently is not supported';

        return;
    }

    # create upstream repo
    if ( $self->upstream ) {
        return if !$self->_create_upstream;
    }

    # copy files
    my $files = Pcore::Util::File::Tree->new;

    $files->add_dir( $ENV->share->get_storage( 'pcore', 'Pcore' ) . '/dist/' );

    if ( $self->upstream ) {
        if ( $self->scm eq 'hg' ) {
            $files->add_dir( $ENV->share->get_storage( 'pcore', 'Pcore' ) . '/hg/' );
        }
        elsif ( $self->scm eq 'git' || $self->scm eq 'hg-git' ) {
            $files->add_dir( $ENV->share->get_storage( 'pcore', 'Pcore' ) . '/git/' );
        }
    }

    $files->move_file( 'lib/Module.pm', 'lib/' . $self->namespace =~ s[::][/]smgr . '.pm' );

    $files->render_tmpl( $self->tmpl_params );

    $files->write_to( $self->target_path );

    my $dist = Pcore::Dist->new( $self->target_path );

    # update dist after create
    $dist->build->update;

    return $dist;
}

sub _create_upstream ($self) {
    my $upstream_api;

    my $upstream_namespace = $self->upstream_namespace;

    my $repo_name = lc $self->namespace =~ s[::][-]smgr;

    if ( $self->upstream eq 'bitbucket' ) {
        $upstream_namespace ||= $ENV->user_cfg->{'Pcore::API::Bitbucket'}->{'repo_owner'};

        $self->{upstream_repo_id} = "$upstream_namespace/$repo_name";

        $upstream_api = Pcore::API::Bitbucket->new(
            {   repo_owner   => $upstream_namespace,
                repo_name    => $repo_name,
                api_username => $ENV->user_cfg->{'Pcore::API::Bitbucket'}->{'api_username'},
                api_password => $ENV->user_cfg->{'Pcore::API::Bitbucket'}->{'api_password'},
            }
        );
    }

    my $confirm = P->term->prompt( qq[Create upstream repository "$self->{upstream_repo_id}" on @{[$self->upstream]}?], [qw[yes no skip]], enter => 1 );

    if ( $confirm eq 'skip' ) {
        return 1;
    }
    elsif ( $confirm eq 'no' ) {
        $ERROR = 'Error creating upstream repository';

        return;
    }

    print 'Creating upstream repository ... ';

    my $res = $upstream_api->create_repository( is_private => $self->private, scm => $self->scm );

    if ( !$res->is_success ) {
        $ERROR = 'Error creating upstream repository';

        say 'error';

        return;
    }

    say 'done';

    return if !$self->_clone_upstream;

    if ( !$self->_clone_upstream_wiki ) {
        P->file->rmtree( $self->target_path );

        return;
    }

    return 1;
}

sub _clone_upstream ($self) {
    print 'Cloning upstream repository ... ';

    if ( Pcore::API::SCM->scm_clone( $self->target_path, "ssh://hg\@bitbucket.org/$self->{upstream_repo_id}" ) ) {
        say 'done';

        return 1;
    }
    else {
        $ERROR = 'Error cloning upstream repository';

        say 'error';

        return;
    }
}

sub _clone_upstream_wiki ($self) {
    print 'Cloning upstream wiki ... ';

    if ( Pcore::API::SCM->scm_clone( $self->target_path . '/wiki/', "ssh://hg\@bitbucket.org/$self->{upstream_repo_id}/wiki" ) ) {
        say 'done';

        return 1;
    }
    else {
        $ERROR = 'Error cloning upstream wiki';

        say 'error';

        return;
    }
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
