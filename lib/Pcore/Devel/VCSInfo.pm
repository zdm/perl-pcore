package Pcore::Devel::VCSInfo;

use Pcore qw[-class];

has root => ( is => 'ro', isa => Str, required => 1 );

has vcs             => ( is => 'lazy', isa => Str,  init_arg => undef );
has is_hg           => ( is => 'lazy', isa => Bool, init_arg => undef );
has is_git          => ( is => 'lazy', isa => Bool, init_arg => undef );
has real_vcs        => ( is => 'lazy', isa => Str,  init_arg => undef );
has real_vcs_is_git => ( is => 'lazy', isa => Bool, init_arg => undef );
has uri => ( is => 'lazy', isa => Maybe [ InstanceOf ['Pcore::Util::URI'] ], init_arg => undef );
has is_bitbucket   => ( is => 'lazy', isa => Bool, init_arg => undef );
has is_github      => ( is => 'lazy', isa => Bool, init_arg => undef );
has base_path      => ( is => 'lazy', isa => Str,  init_arg => undef );    # /<owner>/<project>, without .git at the end
has homepage       => ( is => 'lazy', isa => Str,  init_arg => undef );
has repo_web       => ( is => 'lazy', isa => Str,  init_arg => undef );
has repo_url       => ( is => 'lazy', isa => Str,  init_arg => undef );
has repo_type      => ( is => 'lazy', isa => Str,  init_arg => undef );
has bugtracker_web => ( is => 'lazy', isa => Str,  init_arg => undef );

no Pcore;

sub _build_vcs ($self) {
    if ( -d $self->root . '/.hg' ) {
        return 'hg';
    }
    elsif ( -d $self->root . '/.git' ) {
        return 'git';
    }

    return q[];
}

sub _build_is_hg ($self) {
    return $self->vcs eq 'hg' ? 1 : 0;
}

sub _build_is_git ($self) {
    return $self->vcs eq 'git' ? 1 : 0;
}

sub _build_real_vcs ($self) {
    if ( $self->vcs eq 'hg' ) {
        if ( -d $self->root . '/.hg/git' ) {
            return 'git';
        }
        else {
            return 'hg';
        }
    }
    elsif ( $self->vcs eq 'git' ) {
        return 'git';
    }
    else {
        return q[];
    }
}

sub _build_real_vcs_is_git ($self) {
    return $self->real_vcs eq 'git' ? 1 : 0;
}

sub _build_uri ($self) {
    my $uri;

    if ( $self->is_hg ) {
        if ( -f $self->root . '/.hg/hgrc' ) {
            my $cfg = P->file->read_text( $self->root . '/.hg/hgrc' );

            $uri = $1 if $cfg->$* =~ /default\s*=\s*(.+?)$/sm;
        }
    }
    elsif ( $self->is_git ) {
        if ( -f $self->root . '/.git/config' ) {
            my $cfg = P->file->read_text( $self->root . '/.git/config' );

            $uri = $1 if $cfg->$* =~ /\s*url\s*=\s*(.+?)$/sm;
        }
    }

    if ($uri) {
        $uri = 'http://' . $uri if index( $uri, q[://], 0 ) == -1;

        $uri = P->uri($uri);
    }

    return $uri;
}

sub _build_is_bitbucket ($self) {
    return $self->uri && $self->uri->host eq 'bitbucket.org' ? 1 : 0;
}

sub _build_is_github ($self) {
    return $self->uri && $self->uri->host eq 'github.com' ? 1 : 0;
}

sub _build_base_path ($self) {
    if ( $self->uri ) {
        if ( $self->real_vcs_is_git ) {
            if ( $self->uri->port ) {
                return q[/] . $self->uri->port . q[/] . $self->uri->path->filename_base;
            }
            else {
                return q[/] . $self->uri->path->dirname . $self->uri->path->filename_base;
            }
        }
        else {
            return $self->uri->path->to_string;
        }
    }
    else {
        return q[];
    }
}

sub _build_homepage ($self) {
    if ( $self->is_bitbucket ) {
        return 'https://bitbucket.org' . $self->base_path . '/overview';
    }
    elsif ( $self->is_github ) {
        return 'https://github.com' . $self->base_path;
    }
    else {
        return q[];
    }
}

sub _build_repo_web ($self) {
    return $self->homepage;
}

sub _build_repo_url ($self) {
    if ( $self->uri ) {
        if ( $self->real_vcs_is_git ) {
            return 'https://' . $self->uri->host . $self->base_path . q[.git];
        }
        else {
            return 'https://' . $self->uri->host . $self->base_path;
        }
    }
    else {
        return q[];
    }

}

sub _build_repo_type ($self) {
    return $self->real_vcs;
}

sub _build_bugtracker_web ($self) {
    if ( $self->is_bitbucket ) {
        return 'https://bitbucket.org' . $self->base_path . '/issues?status=new&status=open';
    }
    elsif ( $self->is_github ) {
        return 'https://github.com' . $self->base_path . '/issues?q=is%3Aopen+is%3Aissue';
    }
    else {
        return q[];
    }
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Devel::VCSInfo

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
