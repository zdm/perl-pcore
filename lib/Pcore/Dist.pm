package Pcore::Dist;

use Pcore qw[-class];
use Config qw[];

has root => ( is => 'ro', isa => Maybe [Str], required => 1 );    # absolute path to the dist root
has is_installed => ( is => 'ro', isa => Bool, required => 1 );   # dist is installed as CPAN module, root is undefined
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

around new => sub ( $orig, $self, $dist ) {
    my $path;

    my $module;

    if ( $dist =~ /[.]pm\z/smo ) {
        $module = $dist;
    }
    elsif ( $dist =~ m[[./]]smo ) {
        $path = $dist;
    }
    else {
        $module = $dist =~ s[(?:::|-)][/]smgr . '.pm';
    }

    my $args;

    if ($path) {
        if ( $ENV{PAR_TEMP} && $path eq $ENV{PAR_TEMP} ) {
            $args = {
                root         => undef,
                is_installed => 1,
                share_dir    => P->path( $ENV{PAR_TEMP} . '/inc/share/' )->to_string,
            };
        }
        else {
            if ( my $root = $self->find_dist_root($path) ) {
                $args = {
                    root         => $root->to_string,
                    is_installed => 0,
                    share_dir    => $root . 'share/',
                };
            }
            else {

                # path is not a part of a dist
                return;
            }
        }
    }
    else {
        my $module_path;

        if ( exists $INC{$module} ) {
            $module_path = $INC{$module};
        }
        else {
            for my $inc (@INC) {
                next if ref $inc;

                if ( -f "$inc/$module" ) {
                    $module_path = "$inc/$module";

                    last;
                }
            }
        }

        # module was not found in @INC
        return if !$module_path;

        my $lib = $module_path;

        die q[Module path is not related to lib, please report] if $lib !~ s/\Q$module\E\z//sm;

        # convert Module/Name.pm to Dist-Name
        my $dist_name = $module =~ s[/][-]smgr;

        $dist_name =~ s/[.]pm\z//sm;

        if ( -f "$lib/auto/share/dist/$dist_name/dist.perl" ) {

            # module is installed
            $args = {
                root             => undef,
                is_installed     => 1,
                share_dir        => $lib . "auto/share/dist/$dist_name/",
                main_module_path => $module_path,
            };
        }
        elsif ( -f "$lib/../share/dist.perl" ) {
            my $root = P->path("$lib/../")->realpath;

            # module is a dist
            $args = {
                root             => $root->to_string,
                is_installed     => 0,
                share_dir        => $root . 'share/',
                main_module_path => $module_path,
            };
        }
        else {

            # module is not a dist main module
            return;
        }
    }

    return $self->$orig($args);
};

no Pcore;

# CLASS METHODS
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

# CONSTRUCTOR
sub create ( $self, @args ) {
    return P->class->load('Pcore::Dist::Build')->new->create(@args);
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
    my $module = $self->name =~ s[-][/]smgr . '.pm';

    my $path;

    if ( $self->is_installed ) {
        if ( exists $INC{$module} ) {
            $path = $INC{$module};
        }
        else {
            for my $inc (@INC) {
                next if ref $inc;

                if ( -f "$inc/$module" ) {
                    $path = "$inc/$module";

                    last;
                }
            }
        }
    }
    else {
        $path = $self->root . 'lib/' . $module;
    }

    die 'Main module was not found, this is totally unexpected...' if !$path || !-f $path;

    return $path;
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
## │    3 │ 1                    │ Modules::ProhibitExcessMainComplexity - Main code has high complexity score (21)                               │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 149                  │ ValuesAndExpressions::ProhibitMismatchedOperators - Mismatched operator                                        │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 224                  │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
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
