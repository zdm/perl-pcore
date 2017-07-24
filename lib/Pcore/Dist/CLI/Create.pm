package Pcore::Dist::CLI::Create;

use Pcore -class;
use Pcore::Dist;
use Pcore::API::SCM::Const qw[:ALL];

with qw[Pcore::Core::CLI::Cmd];

# CLI
sub CLI ($self) {
    return {
        abstract => 'create new distribution',
        name     => 'new',
        opt      => {
            cpan => {
                desc    => 'create CPAN distribution',
                default => 0,
            },
            hosting => {
                short   => undef,
                desc    => qq[define hosting for upstream repository. Possible values: '$SCM_HOSTING_BITBUCKET', '$SCM_HOSTING_GITHUB'],
                isa     => [ $SCM_HOSTING_BITBUCKET, $SCM_HOSTING_GITHUB ],
                default => $SCM_HOSTING_BITBUCKET,
            },
            private => {
                desc    => 'upstream repository is private',
                default => 0,
            },
            upstream_scm_type => {
                short   => undef,
                desc    => qq[upstream repository SCM type. Possible values: '$SCM_TYPE_HG', '$SCM_TYPE_GIT'],
                isa     => [ $SCM_TYPE_HG, $SCM_TYPE_GIT ],
                default => $SCM_TYPE_HG,
            },
            local_scm_type => {
                short   => undef,
                desc    => qq[local repository SCM type. Possible values: '$SCM_TYPE_HG', '$SCM_TYPE_GIT'],
                isa     => [ $SCM_TYPE_HG, $SCM_TYPE_GIT ],
                default => $SCM_TYPE_HG,
            },
            upstream_namespace => {
                short => undef,
                desc  => 'upstream repository namespace',
                isa   => 'Str',
            },
        },
        arg => [    #
            dist_namespace => { type => 'Str', },
        ],
    };
}

sub CLI_RUN ( $self, $opt, $arg, $rest ) {
    $opt->{dist_namespace} = $arg->{dist_namespace};

    $opt->{base_path} = $ENV->{START_DIR};

    require Pcore::Dist::Build;

    my ( $status, $dist ) = Pcore::Dist::Build->new->create($opt);

    exit 3 if !$status;

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::CLI::Create - create new distribution

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
