package Pcore::Dist;

use Pcore -class;
use Config;

has root => ( is => 'ro', isa => Maybe [Str], required => 1 );    # absolute path to the dist root
has is_installed => ( is => 'ro', isa => Bool, required => 1 );   # dist is installed as CPAN module, root is undefined
has share_dir    => ( is => 'ro', isa => Str,  required => 1 );   # absolute path to the dist share dir

has module => ( is => 'lazy', isa => InstanceOf ['Pcore::Util::Perl::Module'], predicate => 1 );

has build_info => ( is => 'lazy', isa => Maybe [HashRef], clearer => 1, init_arg => undef );
has cfg => ( is => 'lazy', isa => HashRef, clearer => 1, init_arg => undef );
has name     => ( is => 'lazy', isa => Str,  init_arg => undef );                   # Dist-Name
has is_pcore => ( is => 'lazy', isa => Bool, init_arg => undef );
has is_main  => ( is => 'ro',   isa => Bool, default  => 0, init_arg => undef );    # main process dist

has version => ( is => 'lazy', isa => Object, clearer => 1, init_arg => undef );
has last_release_version => ( is => 'lazy', isa => Maybe [Object], clearer => 1, init_arg => undef );
has revision   => ( is => 'lazy', isa => Str, clearer => 1, init_arg => undef );
has build_date => ( is => 'lazy', isa => Str, clearer => 1, init_arg => undef );
has has_uncommited_changes => ( is => 'lazy', isa => Maybe [Bool], clearer => 1, init_arg => undef );    # undef - unknown
has scm => ( is => 'lazy', isa => Maybe [ InstanceOf ['Pcore::Src::SCM'] ], init_arg => undef );

has build => ( is => 'lazy', isa => InstanceOf ['Pcore::Dist::Build'], init_arg => undef );

around new => sub ( $orig, $self, $dist ) {

    # PAR dist processing
    if ( $ENV{PAR_TEMP} && $dist eq $ENV{PAR_TEMP} ) {

        # dist is the PAR dist
        return $self->$orig(
            {   root         => undef,
                is_installed => 1,
                share_dir    => P->path( $ENV{PAR_TEMP} . '/inc/share/' )->to_string,
            }
        );
    }

    my $module_name;

    if ( substr( $dist, -3, 3 ) eq '.pm' ) {

        # if $dist contain .pm suffix - this is a full or related module name
        $module_name = $dist;
    }
    elsif ( $dist =~ m[[./\\]]smo ) {

        # if $dist doesn't contain .pm suffix, but contain ".", "/" or "\" - this is a path
        # try find dist by path
        if ( my $root = $self->find_dist_root($dist) ) {

            # path is a part of the dist
            return $self->$orig(
                {   root         => $root->to_string,
                    is_installed => 0,
                    share_dir    => $root . 'share/',
                }
            );
        }
        else {

            # path is NOT a part of a dist
            return;
        }
    }
    else {

        # otherwise $dist is a Package::Name
        $module_name = $dist =~ s[(?:::|-)][/]smgr . '.pm';
    }

    # find dist by module name
    my $module_lib;

    # find full module path
    if ( $module_lib = $INC{$module_name} ) {

        # if module is already loaded - get full module path from %INC
        # cut module name, throw error in case, where: 'Module/Name.pm' => '/path/to/Other/Module.pm'
        die q[Invalid module name in %INC, please report] if $module_lib !~ s[[/\\]\Q$module_name\E\z][]sm;
    }
    else {

        # or try to find module in @INC
        for my $inc (@INC) {
            next if ref $inc;

            if ( -f "$inc/$module_name" ) {
                $module_lib = $inc;

                last;
            }
        }
    }

    # module was not found in @INC
    return if !$module_lib;

    # normalize module lib
    $module_lib = P->path( $module_lib, is_dir => 1 )->to_string;

    # convert Module/Name.pm to Dist-Name
    my $dist_name = $module_name =~ s[/][-]smgr;

    # remove .pm suffix
    substr $dist_name, -3, 3, q[];

    if ( -f $module_lib . "auto/share/dist/$dist_name/dist.perl" ) {

        # module is installed
        return $self->$orig(
            {   root         => undef,
                is_installed => 1,
                share_dir    => $module_lib . "auto/share/dist/$dist_name/",
                module       => P->perl->module( $module_name, $module_lib ),
            }
        );
    }
    elsif ( $self->dir_is_dist("$module_lib/../") ) {
        my $root = P->path("$module_lib/../")->to_string;

        # module is a dist
        return $self->$orig(
            {   root         => $root,
                is_installed => 0,
                share_dir    => $root . 'share/',
                module       => P->perl->module( $module_name, $module_lib ),
            }
        );
    }

    return;
};

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
sub _build_module ($self) {
    my $module_name = $self->name =~ s[-][/]smgr . '.pm';

    my $module;

    if ( $self->is_installed ) {

        # find main module in @INC
        $module = P->perl->module($module_name);
    }
    elsif ( -f $self->root . 'lib/' . $module_name ) {

        # we check -f manually, because perl->module will search for Module/Name.pm in whole @INC, but we need only to search module in dist root
        # get main module from dist root lib
        $module = P->perl->module( $module_name, $self->root . 'lib/' );
    }

    die qq[Distr main module "$module_name" wasn't found, distribution is corrupted] if !$module;

    return $module;
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

sub _build_is_pcore ($self) {
    return $self->name eq 'Pcore';
}

sub _build_version ($self) {
    if ( $self->is_installed ) {
        return version->new( $self->build_info->{version} );
    }
    else {
        return $self->module->version;
    }
}

sub _build_last_release_version ($self) {
    if ( $self->scm ) {
        if ( my @releases = sort { $b cmp $a } grep {/v\d+[.]\d+[.]\d+/sm} $self->scm->server->cmd(qw[tags -q])->{o}->@* ) {
            return version->parse( $releases[0] );
        }
        else {
            return version->parse('v0.0.0');
        }
    }
    else {
        return;
    }
}

sub _build_revision ($self) {
    my $revision = 0;

    if ( $self->is_installed ) {
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
    if ( $self->is_installed ) {
        return $self->build_info->{build_date};
    }
    else {
        return P->date->now_utc->to_string;
    }
}

sub _build_has_uncommited_changes ($self) {
    if ( $self->scm ) {
        if ( $self->scm->server->cmd(qw[status -mardu --subrepos])->%* ) {
            return 1;
        }
        else {
            return 0;
        }
    }
    else {
        return;
    }
}

sub _build_scm ($self) {
    return if $self->is_installed;

    return P->class->load('Pcore::Src::SCM')->new( $self->root );
}

sub _build_build ($self) {
    return P->class->load('Pcore::Dist::Build')->new( { dist => $self } );
}

sub create_build_info ($self) {
    my $data = {
        version    => $self->version->normal,
        revision   => $self->revision,
        build_date => $self->build_date,
    };

    return P->data->to_perl( $data, readable => 1 );
}

sub clear ($self) {
    $self->module->clear if $self->has_module;

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
## │    3 │ 110, 160             │ ValuesAndExpressions::ProhibitMismatchedOperators - Mismatched operator                                        │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 261                  │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 218, 237, 261        │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 218                  │ BuiltinFunctions::ProhibitReverseSortBlock - Forbid $b before $a in sort blocks                                │
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
