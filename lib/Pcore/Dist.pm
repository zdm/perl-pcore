package Pcore::Dist;

use Pcore qw[-class];
use Config qw[];

has root => ( is => 'ro', isa => Maybe [Str], required => 1 );    # absolute path to the dist root
has is_installed => ( is => 'ro', isa => Bool, required => 1 );   # dist is installed as CPAN module, root is undefined
has is_par       => ( is => 'ro', isa => Bool, required => 1 );   # dist is used as PAR
has share_dir    => ( is => 'ro', isa => Str,  required => 1 );   # absolute path to the dist share dir
has main_module_path => ( is => 'lazy', isa => Str );             # absolute path

has main_module => ( is => 'lazy', isa => InstanceOf ['Pcore::Util::Perl::ModuleInfo'], clearer => 1, init_arg => undef );
has build_info => ( is => 'lazy', isa => Maybe [HashRef], clearer => 1, init_arg => undef );
has cfg => ( is => 'lazy', isa => HashRef, clearer => 1, init_arg => undef );
has name       => ( is => 'lazy', isa => Str,    init_arg => undef );                  # Dist-Name
has ns         => ( is => 'lazy', isa => Str,    init_arg => undef );                  # Dist::Name
has version    => ( is => 'lazy', isa => Object, clearer  => 1, init_arg => undef );
has revision   => ( is => 'lazy', isa => Str,    clearer  => 1, init_arg => undef );
has build_date => ( is => 'lazy', isa => Str,    clearer  => 1, init_arg => undef );
has scm => ( is => 'lazy', isa => Maybe [ InstanceOf ['Pcore::Src::SCM'] ], init_arg => undef );

has build => ( is => 'lazy', isa => InstanceOf ['Pcore::Dist::Build'], init_arg => undef );

around new => sub ( $orig, $self, $path ) {
    my $pkg_name;

    if ( $path =~ /[.]pm\z/smo ) {                                                     # Package/Name.pm
        $pkg_name = $path;
    }
    elsif ( $ENV{PAR_TEMP} && $path eq $ENV{PAR_TEMP} ) {                              # PAR
        return $self->$orig(
            {   root         => undef,
                is_installed => 1,
                is_par       => 1,
                share_dir    => P->path( $ENV{PAR_TEMP} . '/inc/share/' )->to_string,
            }
        );
    }
    elsif ( $path =~ m[[./]]smo ) {                                                    # ./path/to/dist
        if ( $path = $self->find_dist_root($path) ) {
            return $self->$orig(
                {   root         => $path->to_string,
                    is_installed => 0,
                    is_par       => 0,
                    share_dir    => $path . 'share/',
                }
            );
        }
        else {
            return;
        }
    }
    else {    # Package::Name
        $pkg_name = $path =~ s[::][/]smgro . q[.pm];
    }

    my $pkg_inc;

    # try to find package in the @INC
    for my $inc (@INC) {
        next if ref $inc;

        if ( -f $inc . q[/] . $pkg_name ) {
            $pkg_inc = $inc;

            last;
        }
    }

    # package was found
    if ($pkg_inc) {
        my $dist_name = $pkg_name =~ s[/][-]smgro;

        substr $dist_name, -3, 3, q[];    # remove ".pm" suffix

        if ( -f $pkg_inc . qq[/auto/share/dist/$dist_name/dist.perl] ) {

            # package is installed
            return $self->$orig(
                {   root             => undef,
                    is_installed     => 1,
                    is_par           => 0,
                    share_dir        => $pkg_inc . qq[/auto/share/dist/$dist_name/],
                    main_module_path => $pkg_inc . q[/] . $pkg_name,
                }
            );
        }
        elsif ( my $dist_root = $self->find_dist_root($pkg_inc) ) {

            # package is a distribution
            return $self->$orig(
                {   root         => $dist_root->to_string,
                    is_installed => 0,
                    is_par       => 0,
                    share_dir    => $dist_root . 'share/',
                }
            );
        }
    }

    return;
};

no Pcore;

# CLASS METHODS
sub global_cfg ($self) {
    state $cfg = -f $PROC->{PCORE_USER_DIR} . 'config.ini' ? P->cfg->load( $PROC->{PCORE_USER_DIR} . 'config.ini' ) : undef;

    return $cfg;
}

sub find_dist_root ( $self, $path ) {
    $path = P->path( $path, is_dir => 1 ) if !ref $path;

    if ( !$self->dir_is_dist($path) ) {
        $path = $path->parent;

        while ($path) {
            last if $self->dir_is_dist($path);

            $path = $path->parent;
        }
    }

    if ( defined $path ) {
        return $path->realpath;
    }
    else {
        return;
    }
}

sub dir_is_dist ( $self, $path ) {
    return -f $path . '/share/dist.perl' && $path !~ m[/share/pcore/\z]sm ? 1 : 0;
}

# BUILDERS
sub _build_main_module ($self) {
    return P->perl->module_info( $self->main_module_path );
}

sub _build_build_info ($self) {
    return -f $self->share_dir . 'build.perl' ? P->cfg->load( $self->share_dir . 'build.perl' ) : undef;
}

sub _build_cfg ($self) {
    return P->cfg->load( $self->share_dir . 'dist.perl' );
}

sub _build_name ($self) {
    return $self->cfg->{dist}->{name};
}

sub _build_ns ($self) {
    return $self->name =~ s/-/::/smgr;
}

sub _build_main_module_path ($self) {
    my $path = $self->ns =~ s[::][/]smgr . '.pm';

    if ( exists $INC{$path} ) {
        return $INC{$path};
    }
    elsif ( $self->is_installed ) {
        for my $inc (@INC) {
            next if ref $inc;

            return $inc . q[/] . $path if -f $inc . q[/] . $path;
        }
    }
    else {
        return $self->root . 'lib/' . $path;
    }

    die 'Main module was not found, this is totally unexpected...';
}

sub _build_version ($self) {
    if ( $PROC->is_par || $self->is_installed ) {
        return version->new( $self->build_info->{version} );
    }
    else {
        return $self->main_module->version;
    }
}

sub _build_revision ($self) {
    my $revision = 0;

    if ( $PROC->is_par || $self->is_installed ) {
        $revision = $self->build_info->{revision};
    }
    elsif ( $self->scm ) {
        $revision = $self->scm->server->cmd(qw[id -i])->{o}->[0];
    }
    elsif ( $self->root && -f $self->root . '.hg_archival.txt' ) {
        my $info = P->file->read_bin( $self->root . '.hg_archival.txt' );

        if ( $info->$* =~ /^node:\s+([[:xdigit:]]+)$/sm ) {
            $revision = $1;
        }
    }

    return $revision;
}

sub _build_build_date ($self) {
    if ( $PROC->is_par || $self->is_installed ) {
        return $self->build_info->{build_date};
    }
    else {
        return P->date->now_utc->to_string;
    }
}

sub _build_scm ($self) {
    return if $self->is_installed;

    return P->class->load('Pcore::Src::SCM')->new( $self->root );
}

sub _build_build ($self) {
    return P->class->load('Pcore::Dist::Build')->new( { dist => $self } );
}

sub create_build_cfg ($self) {
    my $data = {
        version    => $self->version->normal,
        revision   => $self->revision,
        build_date => $self->build_date,
    };

    return P->data->to_perl( $data, readable => 1 );
}

sub clear ($self) {
    $self->clear_main_module;

    $self->clear_build_info;

    $self->clear_cfg;

    $self->clear_version;

    $self->clear_revision;

    $self->clear_build_date;

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 63, 76, 135, 169     │ ValuesAndExpressions::ProhibitMismatchedOperators - Mismatched operator                                        │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 195                  │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
