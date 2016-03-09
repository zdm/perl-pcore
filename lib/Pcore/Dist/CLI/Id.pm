package Pcore::Dist::CLI::Id;

use Pcore -class;

with qw[Pcore::Dist::CLI];

sub CLI ($self) {
    return {
        abstract => 'show distribution info',
        opt      => {
            pcore => { desc => 'show info about currently used Pcore distribution', },
            all   => { desc => 'show info about all distributions in $PCORE_LIB directory', },
        },
        arg => [
            dist => {
                desc => 'show info about currently used Pcore distribution',
                isa  => 'Str',
                min  => 0,
            },
        ],
    };
}

sub CLI_RUN ( $self, $opt, $arg, $rest ) {
    if ( !$opt->{all} ) {
        my $dist;

        if ( $opt->{pcore} ) {
            $dist = $ENV->pcore;
        }
        elsif ( $arg->{dist} ) {
            if ( $arg->{dist} =~ /\APcore\z/smi ) {
                $dist = $ENV->pcore;
            }
            else {
                $dist = Pcore::Dist->new( $arg->{dist} );
            }
        }

        if ($dist) {
            $self->_show_dist_info($dist);
        }
        else {
            $self->new->run;
        }
    }
    else {
        for my $dir ( P->file->read_dir( $ENV{PCORE_LIB}, full_path => 1 )->@* ) {
            if ( my $dist = Pcore::Dist->new($dir) ) {
                $self->_show_dist_info1($dist);
            }
        }
    }

    return;
}

sub run ( $self ) {
    $self->_show_dist_info( $self->dist );

    return;
}

sub _show_dist_info ( $self, $dist ) {
    my $tmpl = <<'TMPL';
name: <: $dist.name :>
version: <: $dist.version :>
revision: <: $dist.revision :>
installed: <: $dist.is_installed :>
module_name: <: $dist.module.name :>
root: <: $dist.root :>
share_dir: <: $dist.share_dir :>
lib_dir: <: $dist.module.lib :>
TMPL

    say P->tmpl->render( \$tmpl, { dist => $dist } )->$*;

    return;
}

sub _show_dist_info1 ( $self, $dist ) {

    # hg log -r . --template "{latesttag('re:^v\d+[.]\d+[.]\d+$') % '{tag}, {distance}'}"
    my $changes_since_last_release = $dist->scm->server->cmd( qw[log -r . --template], q[{latesttag('re:^v\d+[.]\d+[.]\d+$') % '{distance}'}] )->{o}->[0] - 1;

    state $print_header = do {
        say sprintf( '%-30s    %10s    %16s    %10s    %10s', 'DIST NAME', 'VERSION', 'RELEASED VERSION', 'UNCOMMITED', 'UNRELEASED' );

        1;
    };

    say sprintf( '%-30s    %10s    %16s    %10s    %10s', $dist->name, $dist->version, $dist->last_release_version eq 'v0.0.0' ? q[] : $dist->last_release_version, $dist->has_uncommited_changes ? 'yes' : q[], $changes_since_last_release || q[] );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 32                   │ RegularExpressions::ProhibitFixedStringMatches - Use 'eq' or hash instead of fixed-pattern regexps             │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 84                   │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 12, 84               │ ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 87, 92               │ CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::CLI::Id - show different distribution info

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
