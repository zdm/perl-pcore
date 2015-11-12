package Pcore::Src;

use Pcore qw[-class];
use Pcore::Src::File;
use Term::ANSIColor qw[:constants];

has action => ( is => 'ro', isa => Enum [qw[decompress compress obfuscate hg-pre-commit]], required => 1 );
has source => ( is => 'ro', isa => Str );    # q[-] - stdin, Str - path

# mandatory, if source path is idr
has type => ( is => 'ro', isa => Enum [ map { lc $_->{type} } Pcore::Src::File->cfg->{FILE_TYPE}->@* ] );

# mandatory, if source is stdin
has filename => ( is => 'ro', isa => Str );

has dry_run     => ( is => 'ro', isa => Bool, default => 0 );
has interactive => ( is => 'rw', isa => Bool, default => 0 );    # print report to STDOUT

has exit_code => ( is => 'rw', isa => Int, default => 0, init_arg => undef );
has _total_report => ( is => 'lazy', isa => HashRef, default => sub { {} }, init_arg => undef );

sub run {
    my $self = shift;

    if ( $self->action eq 'hg-pre-commit' ) {                    # mercurial pretxncommit hook
        $self->_action_hg_pre_commit;
    }
    else {
        $self->_throw_error(q["source" is mandatory]) if !$self->source;

        if ( $self->source eq q[-] ) {                           # STDIN mode
            $self->_throw_error(q["filename" is mandatory if source is STDIN]) if !$self->filename;

            $self->_source_stdin;
        }
        else {
            $self->_throw_error(q["source" should be readable]) if !-e $self->source;

            if ( -d $self->source ) {                            # directory mode
                $self->_throw_error(q["type" is required]) if !$self->type;

                $self->_source_dir;
            }
            else {
                $self->_source_file;
            }
        }
    }

    return $self->exit_code;
}

sub _action_hg_pre_commit ($self) {
    my $scm = P->class->load('Pcore::Src::SCM')->new( $PROC->{START_DIR} );

    unless ($scm) {
        $self->_throw_error(q[No hg repository found]);

        return;
    }

    # get commit info
    my $pre_commit = $scm->server->pre_commit;

    # index files, calculate max_path_len
    my @paths_to_process;

    my $max_path_len = 0;

    for my $file ( $pre_commit->{files}->@* ) {
        next if !$file->is_added && !$file->is_modified;

        my $type = Pcore::Src::File->detect_filetype( $file->path );

        next if !$type || $type->{type} ne 'Perl';    # only perl sources processed now

        push @paths_to_process, $file->path;

        $max_path_len = length $file->path if length $file->path > $max_path_len;
    }

    # process files
    {
        my $chdir_guard = P->file->chdir( $scm->root ) or die;

        my $filter_args = { $pre_commit->{message} =~ /#\s*no\scritic/sm ? ( perl_critic => 0 ) : () };

        for (@paths_to_process) {
            $self->_process_file(
                $max_path_len,
                action      => 'decompress',
                path        => $_->to_string,
                is_realpath => 1,
                dry_run     => $self->dry_run,
                filter_args => $filter_args,
            );
        }
    }

    $self->_report_total if $self->interactive;

    return;
}

sub _source_stdin ($self) {
    $self->interactive(0);

    # read STDIN
    my $in_buffer;

    {
        open my $stdin_raw, '<&STDIN' or die;

        binmode $stdin_raw, ':raw' or die;

        $in_buffer = P->file->read_bin($stdin_raw);

        close $stdin_raw or die;
    }

    my $res = $self->_process_file(
        undef,
        action      => $self->action,
        path        => $self->filename,
        is_realpath => 0,
        in_buffer   => $in_buffer,
        dry_run     => $self->dry_run,
    );

    # write STDOUT
    {
        open my $stdout_raw, '>&STDOUT' or die;

        binmode $stdout_raw, ':raw' or die;

        print {$stdout_raw} $res->out_buffer->$*;

        close $stdout_raw or die;
    }

    return;
}

sub _source_dir ($self) {

    # index files, calculate max_path_len
    my @paths_to_process;

    my $max_path_len = 0;

    P->file->finddepth(
        {   wanted => sub {
                return if -d;

                my $path = P->path( $_, is_dir => 0 );

                my $type = Pcore::Src::File->detect_filetype($path);

                return if !$type || lc $type->{type} ne $self->type;    # skip file, if file type isn't supported

                push @paths_to_process, $path;

                $max_path_len = length $path if length $path > $max_path_len;
            },
            no_chdir => 1
        },
        $self->source,
    );

    # process indexed files
    for (@paths_to_process) {
        $self->_process_file(
            $max_path_len,
            action      => $self->action,
            path        => $_,
            is_realpath => 1,
            dry_run     => $self->dry_run,
        );
    }

    $self->_report_total if $self->interactive;

    return;
}

sub _source_file ($self) {
    $self->_process_file(
        length $self->source,
        action      => $self->action,
        path        => $self->source,
        is_realpath => 1,
        dry_run     => $self->dry_run,
    );

    return;
}

sub _throw_error {
    my $self = shift;
    my $msg = shift || q[Unknown error];

    die $msg . $LF;
}

sub _set_exit_code {
    my $self      = shift;
    my $exit_code = shift;

    $self->exit_code($exit_code) if $exit_code > $self->exit_code;
    return $self->exit_code;
}

sub _process_file ( $self, $max_path_len, % ) {
    my $res = Pcore::Src::File->new( { @_[ 2 .. $#_ ] } )->run;

    $self->_set_exit_code( $res->severity_range_is('ERROR') ? Pcore::Src::File->cfg->{EXIT_CODES}->{SOURCE_ERROR} : Pcore::Src::File->cfg->{EXIT_CODES}->{SOURCE_VALID} );

    $self->_report_file( $res, $max_path_len ) if $self->interactive;

    return $res;
}

sub _report_file ( $self, $res, $max_path_len ) {
    $self->_total_report->{changed_files}++ if $res->was_changed;

    my $hl;
    if ( $res->severity_range_is('ERROR') ) {
        $self->_total_report->{severity_range}->{error}++;
        $hl = BOLD RED;
    }
    elsif ( $res->severity_range_is('WARNING') ) {
        $self->_total_report->{severity_range}->{warning}++;
        $hl = YELLOW;
    }
    else {
        $self->_total_report->{severity_range}->{valid}++;
        $hl = BOLD GREEN;
    }

    # print report
    print $hl;
    printf q[%-*s], $max_path_len, $res->path;
    print q[ ] x 2;
    print RESET;

    # severity
    state $reversed_severity = { reverse Pcore::Src::File->cfg->{SEVERITY}->%* };

    print $hl;
    printf q[%10s], $res->severity_range . q[: ];
    print $res->severity . q[(], sprintf q[%-10s], $reversed_severity->{ $res->severity } . q[)];
    print RESET;

    # bytes changed
    my $dif = $res->_out_size - $res->_in_size;
    $dif = qq[+$dif] if $dif > 0;
    print q[ ] x 2;
    printf q[%10s], $res->_in_size;
    printf q[%10s], $res->_out_size;
    print BOLD . ( $dif > 0 ? RED : GREEN );
    print sprintf q[%10s], $dif;
    print RESET, q[ bytes];

    # modified
    say q[ ] x 2, ( $res->was_changed ? BOLD RED . q[modified] : BOLD GREEN . q[not modified] ), RESET;

    return;
}

sub _report_total ($self) {
    my $t = P->text->table;

    $t->set_cols( 'Type', 'Num' );
    $t->align_col( 'Num', 'right' );

    $t->add_row( $self->_wrap_color( 'VALID',   BOLD GREEN ), $self->_wrap_color( $self->_total_report->{severity_range}->{valid}   // 0, BOLD GREEN ) );
    $t->add_row( $self->_wrap_color( 'WARNING', YELLOW ),     $self->_wrap_color( $self->_total_report->{severity_range}->{warning} // 0, YELLOW ) );
    $t->add_row( $self->_wrap_color( 'ERROR',   BOLD RED ),   $self->_wrap_color( $self->_total_report->{severity_range}->{error}   // 0, BOLD RED ) );
    $t->add_row( 'Modified', $self->_total_report->{changed_files} // 0 );

    say $t->render;

    return;
}

sub _wrap_color ( $self, $str, $color ) {
    return $color . $str . RESET;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 247                  │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Src

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
