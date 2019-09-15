package Pcore::API::Git;

use Pcore -class;

has root => ( required => 1 );

has _upstream => ( init_arg => undef );

around new => sub ( $orig, $self, $path, $search = 1 ) {
    $path = P->path($path)->to_abs;

    my $found;

    if ( -d "$path/.git" ) {
        $found = 1;
    }
    elsif ($search) {
        $path = $path->parent;

        while ($path) {
            if ( -d "$path/.git" ) {
                $found = 1;

                last;
            }

            $path = $path->parent;
        }
    }

    return $self->$orig( { root => $path } ) if $found;

    return;
};

sub _scm_cmd ( $self, $cmd, $root = undef, $cb = undef ) {
    my $chdir_guard = $root ? P->file->chdir( $self->{root} ) : undef;

    my @cmd = ( 'git', $cmd->@* );

    # git "clone" and "init" does not support --porcelain -z options
    push @cmd, qw[--porcelain -z] if $cmd->[0] ne 'init' && $cmd->[0] ne 'clone';

    my $proc = P->sys->run_proc(
        \@cmd,
        stdout => 1,
        stderr => 1,
    )->capture->wait;

    my $res;

    if ( $proc->{is_success} ) {
        $res = res 200, $proc->{stdout} ? [ split /\x00/sm, $proc->{stdout}->$* ] : undef;
    }
    else {
        $res = res [ 500, $proc->{stderr} ? ( $proc->{stderr}->$* =~ /\A(.+?)\n/sm )[0] : () ];
    }

    return $cb ? $cb->($res) : $res;
}

# TODO
sub init ( $self, $path ) {
    my $res = P->sys->run_proc( qq[git init -q "$path"], stdout => 1, stderr => 1 )->wait;

    return $res;
}

# TODO
sub clone ( $self, $from, $to ) {
    return;
}

# TODO
sub upstream ($self) {
    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 36                   | Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_scm_cmd' declared but not used     |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 44                   | ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Git

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
