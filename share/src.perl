{   EXIT_CODES => {
        SOURCE_VALID  => 0,
        RUNTIME_ERROR => 1,
        PARAMS_ERROR  => 2,
        SOURCE_ERROR  => 3,
    },
    SEVERITY => {
        VALID    => 0,
        GENTLE   => 1,
        STERN    => 2,
        HARSH    => 3,
        CRUEL    => 4,
        BRUTAL   => 5,
        PERLTIDY => 6,    # perltidy error
        OPEN     => 7,    # file open error
        BINARY   => 8,    # file is binary
        ENCODING => 9,    # couldn't guess encoding
    },
    SEVERITY_RANGE => {
        VALID   => 0,
        WARNING => 1,
        ERROR   => 4,
    },

    FILE_TYPE => [
        {   type        => 'Perl',
            re          => qr/[.](?:pl|t)\z/sm,
            shebang_re  => qr/perl/sm,
            filter_args => {
                perl_critic               => 1,
                perl_compress_end_section => 1,
            },
        },
        {   type        => 'Perl',
            re          => qr/[.]pm\z/sm,
            filter_args => {                #
                perl_critic => 1,
            },
        },
        {   type        => 'Perl',
            re          => qr/[.]perl\z/sm,
            filter_args => {                  #
                perl_critic => 'pcore-config',
            },
        },
        {   type        => 'Perl',
            re          => qr/[.]PL\z/sm,
            filter_args => {
                perl_critic               => 0,
                perl_compress_end_section => 1,
            },
        },
        {   type        => 'Perl',
            re          => qr/\Acpanfile\z/sm,
            filter_args => {                     #
                perl_critic => 0,
            },
        },
        {   type => 'HTML',
            re   => qr/[.]html\z/smi,
        },
        {   type => 'CSS',
            re   => qr/[.]css\z/smi,
        },
        {   type => 'JS',
            re   => qr/[.](?:js|javascript|json)\z/smi,
        },
    ],

    DEFAULT_GUESS_ENCODING => ['cp1251'],

    # http://perltidy.sourceforge.net/perltidy.html
    PERLTIDY => q[--perl-best-practices --tight-secret-operators --continuation-indentation=2 --maximum-line-length=0 --format-skipping --format-skipping-begin="# <<<" --format-skipping-end="# >>>" --converge --nostandard-output --character-encoding=utf8],

    HTML_BEAUTIFY => q[--indent-scripts normal],

    HTML_PACKER_MINIFY => {
        remove_comments => 0,
        remove_newlines => 1,
        html5           => 1,
    },

    JS_BEAUTIFY => q[--indent-size 4 --indent-char " " --indent-level 0 --no-preserve-newlines --max-preserve-newlines 2 --jslint-happy --brace-style collapse --good-stuff],

    JS_HINT => q[--verbose],    # --show-non-errors

    # perlcritic profiles
    PERLCRITIC => {
        common => {
            __autodetect__ => sub {
                return $_[0] !~ /^use\s+Pcore(?:\s|;)/sm;
            },

            __defaults__ => { severity => 1 },

            # CodeLayout
            'CodeLayout::RequireTidyCode' => undef,    # covered by running perltidy separately

            # Documentation
            'Documentation::RequirePodSections' => undef,

            # TestingAndDebugging
            'TestingAndDebugging::RequireUseStrict'   => { equivalent_modules              => 'Pcore' },
            'TestingAndDebugging::RequireUseWarnings' => { equivalent_modules              => 'Pcore' },
            'TestingAndDebugging::ProhibitNoStrict'   => { allow                           => 'subs refs' },
            'TestingAndDebugging::ProhibitNoWarnings' => { allow_with_category_restriction => 1 },

            # InputOutput
            'InputOutput::ProhibitBacktickOperators' => { only_in_void_context => 1 },

            'ControlStructures::ProhibitCascadingIfElse' => { max_elsif => 5 },
            'ControlStructures::ProhibitPostfixControls' => { allow     => 'if unless' },
            'ControlStructures::ProhibitUnlessBlocks'    => undef,

            # ClassHierarchies
            'ClassHierarchies::ProhibitAutoloading' => { severity => 5 },

            # Modules
            'Modules::RequireNoMatchVarsWithUseEnglish' => undef,

            # Modules
            'Modules::ProhibitEvilModules' => {
                modules => join(
                    q[ ],
                    (   'indirect',    # !!! exporting indirect pragma cause random crashes under windows
                    )
                ),
            },

            # Miscellanea
            'Miscellanea::ProhibitUselessNoCritic' => { severity => 4 },

            # Subroutines
            'Subroutines::ProhibitAmpersandSigils'          => { severity           => 4 },
            'Subroutines::ProhibitUnusedPrivateSubroutines' => { private_name_regex => '_(?!_?build_)\w+', },
            'Subroutines::RequireArgUnpacking'              => undef,
            'Subroutines::ProhibitSubroutinePrototypes'     => undef,               # TODO [PCORE-27] - remove this policy, https://github.com/Perl-Critic/Perl-Critic/issues/591

            # References
            'References::ProhibitDoubleSigils' => { severity => 3 },    # TODO [PCORE-27] - up to level 4 when bug with ->%* will be fixed

            # Variables
            'Variables::ProhibitUnusedVariables' => { severity => 4 },
            'Variables::ProhibitReusedNames'     => { severity => 4 },

            # ValuesAndExpressions
            'ValuesAndExpressions::ProhibitInterpolationOfLiterals' => { severity => 3 },
            'Variables::ProhibitPackageVars'                        => undef,
            'Variables::ProhibitPunctuationVars'                    => undef,
            'ValuesAndExpressions::ProhibitVersionStrings'          => undef,
            'ValuesAndExpressions::ProhibitMagicNumbers'            => undef,

            # RegularExpressions
            'RegularExpressions::RequireDotMatchAnything'       => { severity           => 4 },
            'RegularExpressions::RequireLineBoundaryMatching'   => { severity           => 4 },
            'RegularExpressions::RequireExtendedFormatting'     => undef,
            'RegularExpressions::ProhibitEscapedMetacharacters' => { severity           => 4 },
            'RegularExpressions::ProhibitUselessTopic'          => { severity           => 4 },
            'RegularExpressions::ProhibitUnusualDelimiters'     => { allow_all_brackets => 1 },
            'RegularExpressions::RequireBracesForMultiline'     => { allow_all_brackets => 1 },

            # BuiltinFunctions
            'BuiltinFunctions::ProhibitUselessTopic' => { severity => 4 },
        },
        'pcore-script' => {
            __parent__ => 'common',

            __autodetect__ => sub {
                return $_[0] =~ /^use\s+Pcore(?:\s|;)/sm;
            },

            # Modules
            'Modules::ProhibitEvilModules' => {
                modules => join(
                    q[ ],
                    (   'autodie',
                        'indirect',    # !!! exporting indirect pragma cause random crashes under windows

                        '/\Aconstant/',
                        '/\AReadonly/',
                        'Const::Fast',

                        'English',
                        'Encode',

                        'Sys::Hostname',

                        'Scalar::Util',
                        'List::Util',
                        'List::Util::XS',
                        'List::AllUtils',
                        'Hash::Util',
                        'Sub::Util',

                        '/JSON/',
                        '/Data::Dump/',
                        'Data::Printer',
                        'File::Path',
                        'File::Slurp',
                        'File::Temp',
                        'Path::Tiny',
                        'File::Copy',
                        'Cwd',
                        'File::Spec',
                        'File::Basename',
                        'File::Find',
                        '/Digest/',
                        '/Data::UUID/',
                        '/Data::Serializer/',
                        'Capture::Tiny',

                        'HTTP::Tiny',

                        'Sub::Name',
                        'Sub::Identify',

                        'MIME::Base64',
                        '/URI::Escape/',
                        'URL::Encode',
                        '/Geo::IP/',

                        'Moo',
                        'Moo::Role',
                        'MooX::late',

                        '/MooX::Types::MooseLike/',
                        '/Type::Tiny/',
                        '/\ATypes::/',

                        'Bytes::Random::Secure',
                        'Text::ASCIITable',
                    )
                ),
            },
            'Modules::RequireVersionVar'        => undef,
            'Modules::ProhibitMultiplePackages' => undef,

            # ErrorHandling
            'ErrorHandling::RequireCarping' => undef,

            # InputOutput
            'InputOutput::RequireCheckedSyscalls' => {
                severity          => 4,
                functions         => ':builtins',
                exclude_functions => 'print say sleep',
            },
            'InputOutput::RequireCheckedOpen'  => { severity => 4, },
            'InputOutput::RequireCheckedClose' => { severity => 4, },
        },
        'pcore-config' => {
            __parent__ => 'pcore-script',

            # TestingAndDebugging
            'TestingAndDebugging::RequireUseStrict'   => undef,
            'TestingAndDebugging::RequireUseWarnings' => undef,

            # Modules
            'Modules::RequireExplicitPackage' => undef,
            'Modules::RequireEndWithOne'      => undef,

            # ValuesAndExpressions
            'ValuesAndExpressions::RequireInterpolationOfMetachars' => undef,
            'ValuesAndExpressions::ProhibitInterpolationOfLiterals' => undef,
            'ValuesAndExpressions::ProhibitNoisyQuotes'             => undef,
            'ValuesAndExpressions::ProhibitEmptyQuotes'             => undef,
        },
    },
}
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-config" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 54                   │ RegularExpressions::ProhibitFixedStringMatches - Use 'eq' or hash instead of fixed-pattern regexps             │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
