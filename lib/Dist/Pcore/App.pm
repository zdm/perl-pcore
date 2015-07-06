package Dist::Pcore::App;

use Pcore;
use parent qw[Dist::Zilla::App];

sub _default_command_base {
    return 'Dist::Zilla::App::Command';
}

sub prepare_command {
    my $self = shift;

    my ( $cmd, $opt, @args ) = $self->SUPER::prepare_command(@_);

    if ( $cmd->isa('Dist::Zilla::App::Command::new') ) {
        $opt->{provider} = 'Pcore';
    }
    else {
        # chdir to dist root
        if ( my $dist_root = Pcore::Core::Bootstrap::find_dist_root( P->file->cwd ) ) {
            P->file->chdir($dist_root);
        }
        else {
            say q[No dist was found.];

            exit 3;
        }

        if ( $cmd->isa('Dist::Zilla::App::Command::install') ) {
            $opt->{install_command} ||= 'cpanm .';
        }
    }

    return $cmd, $opt, @args;
}

sub execute_command ( $self, $cmd, $opt, @args ) {

    # TODO chdir to dist root

    if ( $cmd->isa('Dist::Zilla::App::Command::new') ) {
        $self->_new( $cmd, $opt, \@args );
    }
    else {
        $self->SUPER::execute_command( $cmd, $opt, @args );

        if ( $cmd->isa('Dist::Zilla::App::Command::clean') ) {
            $self->_clean( $opt, \@args );
        }
    }

    return;
}

sub _clean ( $self, $opt, $args ) {
    my $dirs = [

        # general build
        'blib',

        # Module::Build
        '_build',
    ];

    my $files = [

        # general build
        qw[META.yml MYMETA.json MYMETA.yml],

        # Module::Build
        qw[_build_params Build Build.bat],

        # MakeMaker
        qw[Makefile pm_to_blib],
    ];

    for my $dir ( $dirs->@* ) {
        P->file->rmtree($dir);
    }

    for my $file ( $files->@* ) {
        unlink $file or die qq[Can't unlink "$file"] if -f $file;
    }

    return;
}

sub _new ( $self, $cmd, $opt, $arg ) {
    my $dist = $arg->[0];

    require Dist::Pcore::Dist::Minter;

    my $stash = $cmd->app->_build_global_stashes;

    my $minter = Dist::Pcore::Dist::Minter->_new_from_profile(
        (   exists $stash->{'%Mint'}
            ? [ $stash->{'%Mint'}->provider, $stash->{'%Mint'}->profile ]
            : [ $opt->provider, $opt->profile ]
        ),
        {   chrome          => $cmd->app->chrome,
            name            => $dist,
            _global_stashes => $stash,
        },
    );

    $minter->mint_dist( {} );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 6                    │ Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_default_command_base' declared but │
## │      │                      │ not used                                                                                                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 93, 95               │ Subroutines::ProtectPrivateSubs - Private subroutine/method used                                               │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Dist::Pcore::App

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
