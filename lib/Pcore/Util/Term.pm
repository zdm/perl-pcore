package Pcore::Util::Term;

use Pcore;
use Term::ReadKey qw[];

no Pcore;

sub width ($self) {
    state $required = do {
        require Term::Size::Any;

        Term::Size::Any::_require_any();

        1;
    };

    return scalar Term::Size::Any::chars();
}

sub pause ( $self, @ ) {
    my %args = (
        msg     => 'Press any key to continue...',
        timeout => 0,
        @_[ 1 .. $#_ ],
    );

    print $args{msg};

    Term::ReadKey::ReadMode(3);

    Term::ReadKey::ReadKey( $args{timeout}, $STDIN );

    Term::ReadKey::ReadMode(0);

    print $LF;

    return;
}

sub prompt ( $self, $msg, $opt, @ ) {
    my %args = (
        default => undef,
        enter   => 0,       # user should press ENTER
        echo    => 1,
        timeout => 0,       # timeout, after the default value will be accepted
        @_[ 3 .. $#_ ],
    );

    my $index = {};

    my @opt;

    my $default_match;

    # index opt, remove duplicates
    for my $val ( $opt->@* ) {
        next if exists $index->{$val};

        $index->{$val} = 1;

        push @opt, $val;

        $default_match = 1 if defined $args{default} && $args{default} eq $val;
    }

    die qq[Invalid default value] if defined $args{default} && !$default_match;

    die q[Default value should be specified if timeout is used] if $args{timeout} && !defined $args{default};

    print $msg, ' (', join( q[|], @opt ), ')';

    print " [$args{default}]" if defined $args{default};

    print ': ';

  READ:
    my @possible = ();

    my $input = $self->read_input(
        edit       => 1,
        echo       => $args{echo},
        echo_char  => undef,
        timeout    => $args{timeout},
        clear_echo => 1,
        on_read    => sub ( $input, $char ) {
            @possible = ();

            # stop reading if ENTER is pressed and has default value
            return if !defined $char && $input eq q[] && defined $args{default};

            # scan possible input values
            for my $val (@opt) {
                push @possible, $val if !index $val, $input, 0;
            }

            # say dump [ \@possible, $input, $char ];

            if ( !@possible ) {
                return 0;    # reject last char
            }
            elsif ( @possible > 1 ) {
                if ( !defined $char ) {
                    return -1;    # clear input on ENTER
                }
                else {
                    return 1;     # accept last char
                }
            }
            else {
                if ( $args{enter} ) {
                    if ( !defined $char ) {
                        return;    # ENTER pressed, accept input
                    }
                    else {
                        return 1;    # waiting for ENTER
                    }
                }
                else {
                    return;          # accept input and exit
                }
            }
        }
    );

    $possible[0] = $args{default} if $input eq q[];    # timeout, no user input

    print $possible[0];

    print $LF;

    return $possible[0];
}

sub read_password ( $self, @ ) {
    my %args = (
        msg       => 'Enter password',
        echo      => 1,
        echo_char => q[*],
        @_[ 1 .. $#_ ],
    );

    print $args{msg}, ': ';

    my $input = $self->read_input(
        edit      => 1,
        echo      => $args{echo},
        echo_char => $args{echo_char},
    );

    print $LF;

    return $input;
}

# NOTE on_read callback should return:
# undef - accept input and return;
# -1    - clear input and continue reading;
# 0     - reject last char and continue reading;
# 1     - accept last char and continue reading;
sub read_input ( $self, @ ) {
    my %args = (
        edit       => 1,
        echo       => 1,
        echo_char  => undef,
        timeout    => 0,
        clear_echo => 0,       # clear echo on return
        on_read    => undef,
        @_[ 1 .. $#_ ],
    );

    my $input = q[];

    my $add_char = sub ($char) {
        print $args{echo_char} // $char if $args{echo};

        $input .= $char;

        return;
    };

    my $delete_char = sub {
        if ( length $input ) {
            print "\e[1D\e[K" if $args{echo};

            substr $input, -1, 1, q[];
        }

        return;
    };

    my $clear_echo = sub {
        if ( $args{echo} && defined $input && ( my $len = length $input ) ) {
            print "\e[${len}D\e[K";
        }

        return;
    };

    my $clear_input = sub {
        $clear_echo->();

        $input = q[];

        return;
    };

    Term::ReadKey::ReadMode(3);

  READ:
    my $key = Term::ReadKey::ReadKey( $args{timeout}, $STDIN );

    if ( !defined $key ) {    # timeout
        $input = q[];
    }
    else {
        $args{timeout} = 0;    # drop timout if user start enter something

        $key =~ s/\x0D|\x0A//smg;

        if ( $key eq q[] ) {    # ENTER
            if ( $args{on_read} ) {
                my $on_read = $args{on_read}->( $input, undef );

                if ( defined $on_read ) {
                    $clear_input->() if $on_read == -1;

                    goto READ;
                }
            }
        }
        elsif ( $key =~ /\e/sm ) {    # ESC seq.
            while ( Term::ReadKey::ReadKey( 0, $STDIN ) ne q[~] ) { }    # read and ignore the rest of the ESC seq.

            goto READ;
        }
        elsif ( $key =~ /[[:cntrl:]]/sm ) {                              # control char
            if ( $args{edit} && ord($key) == 8 || ord($key) == 127 ) {    # BACKSPACE, DELETE
                $delete_char->();
            }

            goto READ;
        }
        else {
            # TODO decode to UTF-8 under windows

            if ( $args{on_read} ) {
                my $on_read = $args{on_read}->( $input . $key, $key );

                if ( defined $on_read ) {
                    if ( $on_read == -1 ) {    # clear input
                        $clear_input->();
                    }
                    elsif ( $on_read == 1 ) {    # accept last character
                        $add_char->($key);
                    }

                    goto READ;
                }
                else {                           # accept last char and return
                    $add_char->($key);
                }
            }
            else {
                $add_char->($key);

                goto READ;
            }

        }
    }

    $clear_echo->() if $args{clear_echo};

    Term::ReadKey::ReadMode(0);

    return $input;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 12                   │ Subroutines::ProtectPrivateSubs - Private subroutine/method used                                               │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │                      │ Subroutines::ProhibitExcessComplexity                                                                          │
## │      │ 40                   │ * Subroutine "prompt" with high complexity score (25)                                                          │
## │      │ 160                  │ * Subroutine "read_input" with high complexity score (27)                                                      │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 66                   │ ValuesAndExpressions::ProhibitInterpolationOfLiterals - Useless interpolation of literal string                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 218                  │ RegularExpressions::ProhibitSingleCharAlternation - Use [\x0D\x0A] instead of \x0D|\x0A                        │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=head1 NAME

Pcore::Util::Term

=head1 METHODS

=head2 prompt

Prompting for user input and returns received value.

    my $res = Pcore::Util::Prompt::prompt($query, \@answers, %options);

=over

=item * OPTIONS

=over

=item * default - default value, returned if enter pressed with no input;

=item * confirm - if true, user need to confirm input with enter;

=back

=back

=head2 pause

Blocking wait for any key pressed.

    Pcore::Util::Prompt::pause([$message], %options);

=over

=item * OPTIONS

=over

=item * timeout - timeout in seconds;

=back

=back

=cut
