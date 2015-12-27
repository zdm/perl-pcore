package Pcore::Dist::Build::Deploy;

use Pcore -class;
use Config qw[];

has dist => ( is => 'ro', isa => InstanceOf ['Pcore::Dist'], required => 1 );

has install    => ( is => 'ro', isa => Bool, default => 0 );
has develop    => ( is => 'ro', isa => Bool, default => 0 );
has recommends => ( is => 'ro', isa => Bool, default => 0 );
has suggests   => ( is => 'ro', isa => Bool, default => 0 );
has verbose    => ( is => 'ro', isa => Bool, default => 0 );

# TODO under windows aqquire superuser automatically with use Win32::RunAsAdmin qw[force];

no Pcore;

sub run ($self) {
    my $chdir_guard = P->file->chdir( $self->dist->root );

    # chmod
    $self->_chmod;

    # cpanm
    exit 100 if !$self->_cpanm;

    # install
    exit 101 if $self->install && !$self->_install;

    return;
}

sub _chmod ($self) {
    print 'chmod ... ';

    if ( !$MSWIN ) {
        P->file->find(
            q[.],
            sub ($path) {
                if ( -d $path ) {
                    P->file->chmod( 'rwx------', $path ) or say qq[$!: $path];
                }
                else {
                    my $is_exe;

                    if ( ( $path->dirname eq 'bin/' || $path->dirname eq 'script/' ) && !$path->suffix ) {
                        $is_exe = 1;
                    }
                    elsif ( $path->suffix eq 'sh' || $path->suffix eq 'pl' || $path->suffix eq 't' ) {
                        $is_exe = 1;
                    }

                    if ($is_exe) {
                        P->file->chmod( 'r-x------', $path ) or say qq[$!: $path];
                    }
                    else {
                        P->file->chmod( 'rw-------', $path ) or say qq[$!: $path];
                    }
                }

                chown $>, $), $path or say qq[$!: $path];    # EUID, EGID

                return;
            }
        );
    }

    say 'done';

    return;
}

sub _cpanm ($self) {
    if ( -f 'cpanfile' ) {
        my $cfg = P->cfg->load( $ENV->res->get( '/data/pcore.perl', lib => 'pcore' ) );

        # install known platform exceptions without tests
        if ( exists $cfg->{cpanm}->{ $Config::Config{archname} } && $cfg->{cpanm}->{ $Config::Config{archname} }->@* ) {
            P->sys->system( 'cpanm', '--notest', $cfg->{cpanm}->{ $Config::Config{archname} }->@* ) or return;
        }

        my @args = (    #
            'cpanm',
            '--with-feature', ( $^O =~ /MSWin/sm ? 'windows' : 'linux' ),
            ( $self->develop    ? '--with-develop'    : () ),
            ( $self->recommends ? '--with-recommends' : () ),
            ( $self->suggests   ? '--with-suggests'   : () ),
            ( $self->verbose    ? '--verbose'         : () ),
            '--cpanfile',    'cpanfile',
            '--installdeps', q[.],
        );

        say join q[ ], @args;

        P->sys->system(@args) or return;
    }

    return 1;
}

sub _install ($self) {
    if ( !P->pm->is_superuser ) {
        say qq[Root privileges required to deploy pcore at system level.];

        return;
    }

    my $canon_dist_root = P->path( $self->dist->root )->canonpath;

    my $canon_bin_dir = $canon_dist_root . '/bin';

    my $canon_dist_lib_dir = P->path("$canon_dist_root/../")->realpath->canonpath;

    if ($MSWIN) {

        # set $ENV{PERL5LIB}
        P->sys->system(qq[setx.exe /M PERL5LIB "$canon_dist_root/lib;"]) or return;

        say qq[%PERL5LIB% updated];

        # set $ENV{PCORE_DIST_LIB}
        P->sys->system(qq[setx.exe /M PCORE_DIST_LIB "$canon_dist_lib_dir"]) or return;

        say qq[%PCORE_DIST_LIB% updated];

        # set $ENV{PCORE_RES_LIB}
        P->sys->system(qq[setx.exe /M PCORE_RES_LIB "$canon_dist_lib_dir/resources"]) or return;

        say qq[%PCORE_RES_LIB% updated];

        # update $ENV{PATH}
        state $init = !!require Win32::TieRegistry;

        my $system_path = Win32::TieRegistry->new('LMachine\SYSTEM\CurrentControlSet\Control\Session Manager\Environment')->GetValue('PATH');

        my $env_path = lc $system_path =~ s[/][\\]smgr;

        $canon_bin_dir =~ s[/][\\]smg;

        my $bin_dir_lc = lc $canon_bin_dir;

        if ( $env_path !~ m[\Q$bin_dir_lc\E(?:/|)(?:;|\Z)]sm ) {    # check if pcore bin dir is already in the path
            my @path = grep { $_ && !/\A\h+\z/sm } split /;/sm, $system_path;    # remove empty path tokens, and tokens, consisting only from spaces

            push @path, $canon_bin_dir;

            $ENV{PATH} = join q[;], @path;                                       ## no critic qw[Variables::RequireLocalizedPunctuationVars]

            P->sys->system(qq[setx.exe /M PATH "$ENV{PATH};"]) or return;

            say qq[%PATH% updated];
        }
    }
    else {
        my $data = <<"SH";
export PERL5LIB="$canon_dist_root/lib:\$PERL5LIB"
export PCORE_DIST_LIB="$canon_dist_lib_dir"
export PCORE_RES_LIB="$canon_dist_lib_dir/resources"
export PATH="\$PATH:$canon_bin_dir"
SH

        P->file->write_bin( '/etc/profile.d/pcore.sh', { mode => q[rw-r--r--] }, \$data );

        say '/etc/profile.d script installed';
    }

    return 1;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 103, 119, 124, 129,  │ ValuesAndExpressions::ProhibitInterpolationOfLiterals - Useless interpolation of literal string                │
## │      │ 151                  │                                                                                                                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 134                  │ ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::Build::Deploy - deploy distribution

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
