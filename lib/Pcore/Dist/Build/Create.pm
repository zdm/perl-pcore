package Pcore::Dist::Build::Create;

use Pcore -class, -result;
use Pcore::Dist;
use Pcore::Util::File::Tree;
use Pcore::API::SCM::Const qw[:ALL];
use Pcore::API::SCM;
use Pcore::API::SCM::Upstream;

has base_path      => ( is => 'ro', isa => Str, required => 1 );
has dist_namespace => ( is => 'ro', isa => Str, required => 1 );    # Dist::Name
has dist_name      => ( is => 'ro', isa => Str, required => 1 );    # Dist-Name

has cpan => ( is => 'ro', isa => Bool, default => 0 );
has hosting => ( is => 'ro', isa => Enum [ $SCM_HOSTING_BITBUCKET, $SCM_HOSTING_GITHUB ], default => $SCM_HOSTING_BITBUCKET );
has private => ( is => 'ro', isa => Bool, default => 0 );
has upstream_scm_type => ( is => 'ro', isa => Enum [ $SCM_TYPE_HG, $SCM_TYPE_GIT ], default => $SCM_TYPE_HG );
has local_scm_type    => ( is => 'ro', isa => Enum [ $SCM_TYPE_HG, $SCM_TYPE_GIT ], default => $SCM_TYPE_HG );
has upstream_namespace => ( is => 'ro', isa => Str );

has target_path => ( is => 'lazy', isa => Str,     init_arg => undef );
has tmpl_params => ( is => 'lazy', isa => HashRef, init_arg => undef );

sub BUILDARGS ( $self, $args ) {
    $args->{dist_namespace} =~ s/-/::/smg;
    $args->{dist_name} = $args->{dist_namespace} =~ s/::/-/smgr;

    return $args;
}

sub _build_target_path ($self) {
    return P->path( $self->base_path, is_dir => 1 )->realpath->to_string . lc $self->{dist_name};
}

sub _build_tmpl_params ($self) {
    return {
        dist_name         => $self->{dist_name},                                                         # Package-Name
        dist_path         => lc $self->{dist_name},                                                      # package-name
        module_name       => $self->{dist_namespace},                                                    # Package::Name
        author            => $ENV->user_cfg->{_}->{author},
        author_email      => $ENV->user_cfg->{_}->{email},
        copyright_year    => P->date->now->year,
        copyright_holder  => $ENV->user_cfg->{_}->{copyright_holder} || $ENV->user_cfg->{_}->{author},
        license           => $ENV->user_cfg->{_}->{license},
        cpan_distribution => $self->cpan,
        pcore_version     => $ENV->pcore->version->normal,
    };
}

sub run ($self) {
    if ( -e $self->target_path ) {
        return result [ 500, 'Target path already exists' ];
    }

    # create upstream repo
    if ( $self->{hosting} ) {
        my $res = $self->_create_upstream_repo;

        return $res if !$res;
    }

    # copy files
    my $files = Pcore::Util::File::Tree->new;

    $files->add_dir( $ENV->share->get_storage( 'pcore', 'Pcore' ) . '/dist/' );

    if ( $self->{hosting} ) {
        if ( $self->{local_scm_type} eq $SCM_TYPE_HG ) {
            $files->add_dir( $ENV->share->get_storage( 'pcore', 'Pcore' ) . '/hg/' );
        }
        elsif ( $self->{local_scm_type} eq $SCM_TYPE_GIT ) {
            $files->add_dir( $ENV->share->get_storage( 'pcore', 'Pcore' ) . '/git/' );
        }
    }

    $files->move_file( 'lib/_MainModule.pm', 'lib/' . ( $self->{dist_name} =~ s[-][/]smgr ) . '.pm' );

    # rename share/_dist.perl -> share/dist.perl
    $files->move_file( 'share/_dist.perl', 'share/dist.perl' );

    $files->render_tmpl( $self->tmpl_params );

    $files->write_to( $self->target_path );

    my $dist = Pcore::Dist->new( $self->target_path );

    # update dist after create
    $dist->build->update;

    return result(200), $dist;
}

sub _create_upstream_repo ($self) {
    my ( $upstream_api, $repo_namespace );

    if ( $self->{hosting} eq $SCM_HOSTING_BITBUCKET ) {
        require Pcore::API::Bitbucket;

        $repo_namespace = $self->{upstream_namespace} // $ENV->user_cfg->{BITBUCKET}->{default_repo_namespace};

        $upstream_api = Pcore::API::Bitbucket->new(
            {   repo_namespace => $repo_namespace,
                repo_name      => lc $self->{dist_name},
                scm_type       => $self->{upstream_scm_type},
            }
        );
    }
    elsif ( $self->upstream eq $SCM_HOSTING_GITHUB ) {
        require Pcore::API::GitHub;

        $repo_namespace = $self->{upstream_namespace} // $ENV->user_cfg->{GITHUB}->{default_repo_namespace};

        $upstream_api = Pcore::API::GitHub->new(
            {   repo_namespace => $repo_namespace,
                repo_name      => lc $self->{dist_name},
            }
        );
    }

    my $confirm = P->term->prompt( qq[Create upstream repository "@{[$upstream_api->id]}" on $self->{hosting}?], [qw[yes no exit]], enter => 1 );

    if ( $confirm eq 'no' ) {
        return result 200;
    }
    elsif ( $confirm eq 'exit' ) {
        return result [ 500, 'Creating upstream repository cancelled' ];
    }

    print 'Creating upstream repository ... ';

    my $res = $upstream_api->create_repo( is_private => $self->{private} );

    say $res;

    return $res if !$res;

    return $self->_clone_upstream_repo($repo_namespace);
}

sub _clone_upstream_repo ( $self, $repo_namespace ) {
    my $scm_upstream = Pcore::API::SCM::Upstream->new(
        {   remote_scm_type => $self->{upstream_scm_type},
            hosting         => $self->{hosting},
            repo_namespace  => $repo_namespace,
            repo_name       => lc $self->{dist_name},
        }
    );

    my $clone_uri = $scm_upstream->get_clone_url( $SCM_URL_TYPE_SSH, $self->{local_scm_type} );

    print qq[Cloning upstream repository "$clone_uri" ... ];

    my $res = Pcore::API::SCM->scm_clone( $self->target_path, $clone_uri, $self->{local_scm_type} );

    say $res;

    return $res;
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
