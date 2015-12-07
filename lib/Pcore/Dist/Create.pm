package Pcore::Dist::Create;

use Pcore qw[-class];
use Pcore::Dist;
use Pcore::Util::File::Tree;

has path      => ( is => 'ro', isa => Str,  required => 1 );
has namespace => ( is => 'ro', isa => Str,  required => 1 );    # Dist::Name
has cpan      => ( is => 'ro', isa => Bool, default  => 0 );

has target_path => ( is => 'lazy', isa => Str,     init_arg => undef );
has tmpl_params => ( is => 'lazy', isa => HashRef, init_arg => undef );

no Pcore;

sub BUILDARGS ( $self, $args ) {
    $args->{namespace} =~ s/-/::/smg if $args->{namespace};

    return $args;
}

sub _build_target_path ($self) {
    return P->path( $self->path, is_dir => 1 )->realpath->to_string . lc( $self->namespace =~ s[::][-]smgr );
}

sub _build_tmpl_params ($self) {
    return {
        dist_name          => $self->namespace =~ s/::/-/smgr,                                                              # Package-Name
        dist_path          => lc $self->namespace =~ s/::/-/smgr,                                                           # package-name
        module_name        => $self->namespace,                                                                             # Package::Name
        main_script        => 'main.pl',
        author             => Pcore::Dist->global_cfg->{_}->{author},
        author_email       => Pcore::Dist->global_cfg->{_}->{email},
        copyright_year     => P->date->now->year,
        copyright_holder   => Pcore::Dist->global_cfg->{_}->{copyright_holder} || Pcore::Dist->global_cfg->{_}->{author},
        license            => Pcore::Dist->global_cfg->{_}->{license},
        bitbucket_username => Pcore::Dist->global_cfg->{Bitbucket}->{username} // 'username',
        dockerhub_username => Pcore::Dist->global_cfg->{DockerHub}->{username} // 'username',
        cpan_distribution  => $self->cpan,
    };
}

sub validate ($self) {
    return 'Target path already exists' if -e $self->target_path;

    return qq["~/.pcore/config.ini" was not found, run "pcore setup"] if !Pcore::Dist->global_cfg;

    return;
}

sub run ($self) {
    return if $self->validate;

    my $files = Pcore::Util::File::Tree->new;

    $files->add_dir( $PROC->res->get_storage( 'pcore', 'pcore' ) );

    $files->move_file( 'lib/Module.pm', 'lib/' . $self->namespace =~ s[::][/]smgr . '.pm' );

    $files->render_tmpl( $self->tmpl_params );

    $files->write_to( $self->target_path );

    my $dist = Pcore::Dist->new( $self->target_path );

    # update dist after create
    $dist->build->update;

    return $dist;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 46                   │ ValuesAndExpressions::ProhibitInterpolationOfLiterals - Useless interpolation of literal string                │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::Create

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
