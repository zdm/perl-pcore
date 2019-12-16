package Pcore::Util::Src::Filter;

use Pcore -role, -res, -const;
use Pcore::Util::Src qw[:FILTER_STATUS];
use Pcore::Util::Sys::Proc qw[:PROC_REDIRECT];

has data      => ( required => 1 );
has path      => ( required => 1 );
has has_kolon => ( is       => 'lazy', init_arg => undef );

our $ESLINT;
our $ESLINT_CONN;

around decompress => sub ( $orig, $self, $data, $path = undef, %args ) {
    $self = $self->new( %args, data => $data->$*, path => $path );

    my $res = $self->$orig;

    $data->$* = $self->{data} if $res < $SRC_FATAL;

    return $res;
};

around compress => sub ( $orig, $self, $data, $path = undef, %args ) {
    $self = $self->new( %args, data => $data->$*, path => $path );

    my $res = $self->$orig;

    $data->$* = $self->{data} if $res < $SRC_FATAL;

    return $res;
};

around obfuscate => sub ( $orig, $self, $data, $path = undef, %args ) {
    $self = $self->new( %args, data => $data->$*, path => $path );

    my $res = $self->$orig;

    $data->$* = $self->{data} if $res < $SRC_FATAL;

    return $res;
};

sub _build_has_kolon ($self) {
    return 1 if $self->{data} =~ /<: /sm;

    return 1 if $self->{data} =~ /^: /sm;

    return 0;
}

sub src_cfg ($self) { return Pcore::Util::Src::cfg() }

sub dist_cfg ($self) { return {} }

sub decompress ($self) { return $SRC_OK }

sub compress ($self) { return $SRC_OK }

sub obfuscate ($self) { return $SRC_OK }

sub update_log ( $self, $log = undef ) {return}

sub filter_prettier ( $self, %options ) {
    $ESLINT //= P->sys->run_proc( [ 'softvisio-cli', '--vim' ] );

    return res [ $SRC_FATAL, $ESLINT->{reason} ] if !$ESLINT->is_active && !$ESLINT;

    $ESLINT_CONN ||= P->handle( 'tcp://127.0.0.1:55556', connection_timeout => 3 );

    return res [ $SRC_FATAL, $ESLINT_CONN->{reason} ] if !$ESLINT_CONN;

    # my $dist_options = $self->dist_cfg->{prettier} || $self->src_cfg->{prettier};

    my $msg = {
        command => 'prettier',
        options => {
            %options,
            "printWidth"              => 99999999,
            "tabWidth"                => 4,
            "semi"                    => \1,
            "singleQuote"             => \1,
            "trailingComma"           => "es5",
            "bracketSpacing"          => \1,
            "jsxBracketSameLine"      => \0,
            "arrowParens"             => "always",
            "vueIndentScriptAndStyle" => \1,
            "endOfLine"               => "lf",
            filepath                  => "$self->{path}",
        },
        data => $self->{data},
    };

    $ESLINT_CONN->write( P->data->to_json($msg) . "\n" );

    my $res = $ESLINT_CONN->read_line;

    $res = P->data->from_json($res);

    # unable to run elsint
    if ( !$res->{status} ) {
        $self->update_log( $res->{reason} );

        return $SRC_ERROR;
    }
    else {
        $self->{data} = $res->{result};

        $self->update_log;

        return $SRC_OK;
    }
}

sub filter_eslint ( $self, @options ) {
    $ESLINT //= P->sys->run_proc( [ 'softvisio-cli', '--vim' ] );

    return res [ $SRC_FATAL, $ESLINT->{reason} ] if !$ESLINT->is_active && !$ESLINT;

    $ESLINT_CONN ||= P->handle( 'tcp://127.0.0.1:55556', connection_timeout => 3 );

    return res [ $SRC_FATAL, $ESLINT_CONN->{reason} ] if !$ESLINT_CONN;

    my $root;

    if ( $self->{path} ) {
        my $path = P->path( $self->{path} );

        while ( $path = $path->parent ) {
            if ( -f "$path/package.json" ) {
                $root = $path;

                last;
            }
        }
    }

    my $msg;

    # node project was found
    if ($root) {
        $msg = {
            command => 'eslint',
            options => {
                useEslintrc                   => \1,
                fix                           => \1,
                allowInlineConfig             => \1,
                reportUnusedDisableDirectives => \1,
            },
            path => "$self->{path}",
            data => $self->{data},
        };
    }

    # node project was not found, use default settings
    else {
        state $config = $ENV->{share}->get('/Pcore/data/.eslintrc.yaml');

        $msg = {
            command => 'eslint',
            options => {
                useEslintrc                   => \0,
                fix                           => \1,
                allowInlineConfig             => \1,
                reportUnusedDisableDirectives => \1,
                configFile                    => $config,
            },
            path => "$self->{path}",
            data => $self->{data},
        };
    }

    $ESLINT_CONN->write( P->data->to_json($msg) . "\n" );

    my $res = $ESLINT_CONN->read_line;

    $res = P->data->from_json($res);

    # unable to run elsint
    if ( !$res->{status} ) {
        return res [ $SRC_FATAL, $res->{reason} ];
    }

    my $eslint_log = $res->{result};

    $self->{data} = $eslint_log->[0]->{output} if $eslint_log->[0]->{output};

    # eslint reported no violations
    if ( !$eslint_log->[0]->{messages}->@* ) {
        $self->update_log;

        return $SRC_OK;
    }

    my ( $log, $has_warnings, $has_errors );

    # create table
    my $tbl = P->text->table(
        style => 'compact',
        color => 0,
        cols  => [
            severity => {
                title  => 'Sev.',
                width  => 7,
                align  => 1,
                valign => -1,
            },
            pos => {
                title       => 'Line:Col',
                width       => 15,
                title_align => -1,
                align       => -1,
                valign      => -1,
            },
            rule => {
                title       => 'Rule',
                width       => 30,
                title_align => -1,
                align       => -1,
                valign      => -1,
            },
            desc => {
                title       => 'Description',
                width       => 80,
                title_align => -1,
                align       => -1,
                valign      => -1,
            },
        ],
    );

    $log .= $tbl->render_header;

    my @items;

    for my $msg ( sort { $a->{severity} <=> $b->{severity} || $a->{line} <=> $b->{line} || $a->{column} <=> $b->{column} } $eslint_log->[0]->{messages}->@* ) {
        my $severity_text;

        if ( $msg->{severity} == 1 ) {
            $has_warnings++;

            $severity_text = 'WARN';
        }
        else {
            $has_errors++;

            $severity_text = 'ERROR';
        }

        push @items, [ $severity_text, "$msg->{line}:$msg->{column}", $msg->{ruleId}, $msg->{message} ];
    }

    my $row_line = $tbl->render_row_line;

    $log .= join $row_line, map { $tbl->render_row($_) } @items;

    $log .= $tbl->finish;

    $self->update_log($log);

    if    ($has_errors)   { return $SRC_ERROR }
    elsif ($has_warnings) { return $SRC_WARN }
    else                  { return $SRC_OK }
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 79, 80, 81, 82, 83,  | ValuesAndExpressions::ProhibitInterpolationOfLiterals - Useless interpolation of literal string                |
## |      | 84, 85, 86, 87, 88   |                                                                                                                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 115                  | Subroutines::ProhibitExcessComplexity - Subroutine "filter_eslint" with high complexity score (21)             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 79                   | ValuesAndExpressions::RequireNumberSeparators - Long number not separated with underscores                     |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Src::Filter

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
