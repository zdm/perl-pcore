package Pcore::Src;

use Pcore -class, -ansi, -const, -export;
use Pcore::Util::Text qw[decode_utf8];
use Pcore::Util::Scalar qw[is_path];

our $EXPORT = { CONST => [qw[$SRC_DECOMPRESS $SRC_COMPRESS $SRC_OBFUSCATE $SRC_COMMIT]] };

const our $SRC_DECOMPRESS => 'decompress';
const our $SRC_COMPRESS   => 'compress';
const our $SRC_OBFUSCATE  => 'obfuscate';
const our $SRC_COMMIT     => 'commit';

require Pcore::Src::File;

has action => ( required => 1 );    # Enum [ $SRC_DECOMPRESS, $SRC_COMPRESS, $SRC_OBFUSCATE, $SRC_COMMIT ]
has path => ();                     # Maybe [Str]

has type        => ();              # mandatory, if source path is dir
has filename    => ();              # Str, mandatory, if source is stdin
has stdin_files => (0);             # read list of filenames from stdin

has dry_run     => ();              # Bool
has interactive => ();              # Bool, print report to STDOUT
has no_critic   => ();              # Bool, skip Perl::Critic filter

has exit_code => ( 0, init_arg => undef );
has _total_report => ( init_arg => undef );    # HashRef

# CLI
sub CLI ($self) {
    return {
        help => <<'TXT',
- convert to uft-8;
- strip BOM header;
- convert tabs to spaces;
- trim trailing spaces;
- trim trailing empty strings;
- convert line endings to unix style (\x0A);

Exit codes:

    0 - source is valid;
    1 - run-time error;
    2 - params error;
    3 - source error;
TXT
        opt => {
            action => {
                desc => <<'TXT',
action to perform:
    decompress   unpack sources, DEFAULT;
    compress     pack sources, comments will be deleted;
    obfuscate    applied only for javascript and embedded javascripts, comments will be deleted;
    commit       SCM commit hook
TXT
                isa     => [ $SRC_DECOMPRESS, $SRC_COMPRESS, $SRC_OBFUSCATE, $SRC_COMMIT ],
                default => $SRC_DECOMPRESS,
            },
            type => {
                desc => 'define source files to process. Mandatory, if <source> is a directory. Recognized types: perl, html, css, js',
                isa  => [qw[perl html css js]],
            },
            stdin_files => {
                short   => undef,
                desc    => 'read list of filenames from STDIN',
                default => 0,
            },
            filename => {
                desc => 'mandatory, if read source content from STDIN',
                type => 'Str',
            },
            no_critic => {
                short   => undef,
                desc    => 'skip Perl::Critic filter',
                default => 0,
            },
            dry_run => {
                short   => undef,
                desc    => q[don't save changes],
                default => 0,
            },
            pause => {
                short   => undef,
                desc    => q[don't close console after script finished],
                default => 0,
            },
        },
        arg => [
            path => {
                isa => 'Path',
                min => 0,
            }
        ],
    };
}

sub CLI_RUN ( $self, $opt, $arg, $rest ) {
    P->file->chdir( $ENV->{START_DIR} );

    my $exit_code = eval {
        my $src = Pcore::Src->new( {
            interactive => 1,
            path        => $arg->{path},
            action      => $opt->{action},
            stdin_files => $opt->{stdin_files},
            no_critic   => $opt->{no_critic},
            dry_run     => $opt->{dry_run},
            ( exists $opt->{type}     ? ( type     => $opt->{type} )     : () ),
            ( exists $opt->{filename} ? ( filename => $opt->{filename} ) : () ),
        } );

        $src->run;
    };

    if ($@) {
        say $@;

        return Pcore::Src::File->cfg->{EXIT_CODES}->{RUNTIME_ERROR};
    }

    if ( $opt->{pause} ) {
        print 'Press ENTER to continue...';
        <STDIN>;
    }

    exit $exit_code;
}

# RUN
sub run ($self) {
    if ( $self->{action} eq 'commit' ) {
        $self->{action} = 'decompress';

        $self->{type} = 'perl';
    }

    if ( !defined $self->{path} ) {    # STDIN mode
        if ( $self->{stdin_files} ) {
            $self->_source_stdin_files;
        }
        else {
            $self->_throw_error(q["filename" is mandatory when source is STDIN]) if !$self->{filename};

            $self->_source_stdin;
        }
    }
    else {
        $self->_throw_error(q["path" should be readable]) if !-e $self->{path};

        if ( -d $self->{path} ) {    # directory mode
            $self->_throw_error(q["type" is required when path is directory]) if !$self->{type};

            $self->_source_dir;
        }
        else {
            $self->_source_file;
        }
    }

    return $self->{exit_code};
}

sub _source_stdin_files ($self) {
    my $files = P->file->read_lines(*STDIN);

    # index files, calculate max_path_len
    my @paths_to_process;

    for my $path ( $files->@* ) {
        $path = P->path($path);

        my $type = Pcore::Src::File->detect_filetype($path);

        next if !$type || lc $type->{type} ne $self->{type};    # skip file, if file type isn't supported

        push @paths_to_process, $path;
    }

    # process files
    $self->_process_files(
        \@paths_to_process,
        {   action      => $self->{action},
            is_realpath => 1,
            dry_run     => $self->{dry_run},
            filter_args => { $self->{no_critic} ? ( perl_critic => 0 ) : () },
        }
    );

    return;
}

sub _source_stdin ($self) {
    $self->{interactive} = 0;

    # read STDIN
    my $in_buffer = P->file->read_bin(*STDIN);

    my $path = is_path $self->{filename} ? $self->{filename} : P->path( $self->{filename} );

    my $res = Pcore::Src::File->new( {
        action      => $self->{action},
        path        => $path->encoded,
        is_realpath => 0,
        in_buffer   => $in_buffer,
        dry_run     => $self->{dry_run},
    } )->run;

    $self->_set_exit_code( $res->severity_range_is('ERROR') ? Pcore::Src::File->cfg->{EXIT_CODES}->{SOURCE_ERROR} : Pcore::Src::File->cfg->{EXIT_CODES}->{SOURCE_VALID} );

    # write STDOUT
    print $res->{out_buffer}->$*;

    return;
}

sub _source_dir ($self) {

    # index files, calculate max_path_len
    my @paths_to_process;

    for my $path ( ( P->path( $self->{path} )->read_dir( max_depth => 0, is_dir => 0 ) // [] )->@* ) {
        my $type = Pcore::Src::File->detect_filetype($path);

        next if !$type || lc $type->{type} ne $self->{type};    # skip file, if file type isn't supported

        push @paths_to_process, $path;
    }

    # process indexed files
    $self->_process_files(
        \@paths_to_process,
        {   action      => $self->{action},
            is_realpath => 1,
            dry_run     => $self->{dry_run},
        }
    );

    return;
}

sub _source_file ($self) {
    $self->_process_files(
        [ $self->{path} ],
        {   action      => $self->{action},
            is_realpath => 1,
            dry_run     => $self->{dry_run},
        }
    );

    return;
}

sub _process_files ( $self, $paths, $args ) {
    my ( $prefix, $max_len, $use_prefix );

    # find longest common prefix
    for my $path ( $paths->@* ) {
        $path = P->path($path) if !is_path $path;

        my $dirname = $path->{dirname};

        if ( !defined $prefix ) {
            $prefix = $dirname;

            $max_len = length $path;
        }
        else {
            $max_len = length $path if length $path > $max_len;

            if ( "$prefix\x00$dirname" =~ /^(.*).*\x00\1.*$/sm ) {
                $prefix = $1;

                $use_prefix = 1;
            }
        }
    }

    # find max. path length
    $max_len -= length $prefix if $use_prefix;

    for my $path ( $paths->@* ) {
        my $report_path = $path->encoded;

        $report_path = substr $report_path, length $prefix if $use_prefix;

        my $res = Pcore::Src::File->new( { $args->%*, path => $path->encoded } )->run;    ## no critic qw[ValuesAndExpressions::ProhibitCommaSeparatedStatements]

        $self->_set_exit_code( $res->severity_range_is('ERROR') ? Pcore::Src::File->cfg->{EXIT_CODES}->{SOURCE_ERROR} : Pcore::Src::File->cfg->{EXIT_CODES}->{SOURCE_VALID} );

        $self->_report_file( $res, $report_path, $max_len ) if $self->{interactive};
    }

    $self->_report_total if $self->{interactive};

    return;
}

sub _report_file ( $self, $res, $report_path, $max_path_len ) {
    if ( !$self->{tbl} ) {
        $self->{tbl} = P->text->table(
            style => 'compact',
            cols  => [
                path => {
                    width => $max_path_len + 2,
                    align => -1,
                },
                severity => {
                    width => 25,
                    align => 1,
                },
                size => {
                    width => 10,
                    align => 1,
                },
                size_delta => {
                    title => 'SIZE DELTA',
                    width => 18,
                    align => 1,
                },
                modified => {
                    width => 12,
                    align => 1,
                },
            ],
        );

        print $self->{tbl}->render_header;
    }

    $self->{_total_report}->{changed_files}++ if $res->was_changed;

    my @row;

    # path
    push @row, decode_utf8( $report_path, encoding => $Pcore::WIN_ENC );

    # severity
    my $severity;

    state $reversed_severity = { reverse Pcore::Src::File->cfg->{SEVERITY}->%* };

    if ( $res->severity_range_is('ERROR') ) {
        $self->{_total_report}->{severity_range}->{error}++;

        $severity = $BOLD . $WHITE . $ON_RED;
    }
    elsif ( $res->severity_range_is('WARNING') ) {
        $self->{_total_report}->{severity_range}->{warning}++;

        $severity = $YELLOW;
    }
    else {
        $self->{_total_report}->{severity_range}->{valid}++;

        $severity = $BOLD . $GREEN;
    }

    $severity .= ' ' . $res->severity_range . ": $res->{severity} - $reversed_severity->{ $res->{severity} } " . $RESET;

    push @row, $severity;

    # size
    push @row, $res->_out_size;

    # size delta
    my $dif = $res->_out_size - $res->_in_size;

    if ( $dif > 0 ) {
        push @row, $BOLD . $RED . "+$dif bytes" . $RESET;
    }
    else {
        push @row, $BOLD . $GREEN . "$dif bytes" . $RESET;
    }

    # modified
    push @row, ( $res->was_changed ? $BOLD . $WHITE . $ON_RED . ' modified ' . $RESET : q[ - ] );

    print $self->{tbl}->render_row( \@row );

    return;
}

sub _report_total ($self) {
    if ( $self->{tbl} ) {
        print $self->{tbl}->finish;

        undef $self->{tbl};
    }

    my $tbl = P->text->table(
        style => 'full',
        cols  => [
            type => {
                width => 10,
                align => -1,
            },
            count => {
                width => 10,
                align => 1,
            },
        ],
    );

    print $tbl->render_header;

    print $tbl->render_row( [ $BOLD . $GREEN . 'VALID' . $RESET, $BOLD . $GREEN . ( $self->{_total_report}->{severity_range}->{valid} // 0 ) . $RESET ] );
    print $tbl->render_row( [ $YELLOW . 'WARNING' . $RESET, $YELLOW . ( $self->{_total_report}->{severity_range}->{warning} // 0 ) . $RESET ] );
    print $tbl->render_row( [ $BOLD . $RED . 'ERROR' . $RESET, $BOLD . $RED . ( $self->{_total_report}->{severity_range}->{error} // 0 ) . $RESET ] );
    print $tbl->render_row( [ 'Modified', $self->{_total_report}->{changed_files} // 0 ] );

    print $tbl->finish;

    return;
}

sub _throw_error ( $self, $msg = 'Unknown error' ) {
    die $msg . $LF;
}

sub _set_exit_code ( $self, $exit_code ) {
    $self->{exit_code} = $exit_code if $exit_code > $self->{exit_code};

    return $self->{exit_code};
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 299                  | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 271                  | ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 359                  | ValuesAndExpressions::ProhibitEmptyQuotes - Quotes used with a string containing no non-whitespace characters  |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Src - Source formatter

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
