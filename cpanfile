requires 'perl', 5.20.2;

# Pcore::Core
requires 'namespace::clean';
requires 'multidimensional';

feature windows => sub {
    requires 'Win32::Console';
    requires 'Win32::Console::ANSI';
};

requires 'Import::Into';
requires 'Variable::Magic';
requires 'B::Hooks::AtRuntime';
requires 'B::Hooks::EndOfScope::XS';
requires 'Const::Fast';

# Pcore::Core::Dump
requires 'PerlIO::Layers';
requires 'Sort::Naturally';

# OOP
requires 'Moo';
requires 'Class::XSAccessor';    # optional
requires 'Type::Tiny';
requires 'Type::Tiny::XS';

# AnyEvent
suggests 'Coro';
requires 'EV';
feature linux => sub {
    requires 'IO::AIO';
};
requires 'AnyEvent';
requires 'Net::DNS::Resolver';

# Inline
requires 'Inline';
requires 'Inline::C';

# Handle
requires 'BerkeleyDB';

# Pcore::Core::CLI
requires 'Getopt::Euclid';    # TODO remove

# Pcore::HTTP
requires 'HTTP::Parser::XS';

# Pcore::Src
requires 'Perl::Tidy';
on develop => sub {
    requires 'Perl::Stripper';
    requires 'Perl::Strip';
    suggests 'Perl::Lint';    # Perl::Critic replacement
    requires 'Perl::Critic';
    requires 'PPI::XS';
    requires 'JavaScript::Packer';
    requires 'CSS::Packer';
    requires 'HTML::Packer';
};

# Pcore::Util::Base64
requires 'MIME::Base64';

# Pcore::Util::Capture
requires 'Capture::Tiny';

# Pcore::Util::Class
requires 'Sub::Util';

# Pcore::Util::Data
requires 'YAML::XS';
requires 'JSON::XS';
requires 'CBOR::XS';
requires 'XML::Hash::XS';
requires 'Config::INI';
requires 'Crypt::CBC';
requires 'Crypt::DES';
requires 'Compress::Zlib';
requires 'URI::Escape::XS';
requires 'WWW::Form::UrlEncoded::XS';

# Pcore::Util::Date
requires 'HTTP::Date';
requires 'Time::Zone';
requires 'Time::Moment';

# Pcore::Util::Digest
requires 'Digest';
requires 'Digest::MD5';
requires 'Digest::Bcrypt';

# Pcore::Util::File
requires 'File::Copy::Recursive';

# Pcore::Util::GeoIP
requires 'Geo::IP::PurePerl';
feature linux => sub {
    requires 'Geo::IP';
};

# Pcore::Util::List
requires 'List::Util::XS';
requires 'List::AllUtils';

# Pcore::Util::Mail
requires 'Net::SMTPS';
requires 'Mail::IMAPClient';

# Pcore::Util::PM
feature linux => sub {
    requires 'Proc::ProcessTable';
};
feature windows => sub {
    requires 'Win32::Service';
};

# Pcore::Util::Prompt
requires 'Term::ReadKey';

# Pcore::Util::Random
requires 'Bytes::Random::Secure';
requires 'Math::Random::ISAAC::XS';
requires 'Crypt::Random::Seed';

# Pcore::Util::Sys
requires 'Sys::CpuAffinity';
requires 'Term::Size::Any';
feature windows => sub {
    requires 'Term::Size::Win32';
};

# Pcore::Util::Text
requires 'HTML::Entities';

# Pcore::Util::Text::Table
requires 'Text::ASCIITable';

# Pcore::Util::Template
requires 'Text::Xslate';
requires 'Text::Xslate::Bridge::TT2Like';

# Pcore::Util::URI
requires 'URI';

# Pcore::Util::UUID
requires 'Data::UUID';

on develop => sub {
    requires 'Module::Build::Tiny';

    # Dist::Zilla family
    feature windows => sub {
        requires 'DateTime::TimeZone::Local::Win32';    # required by Dist::Zilla on windows
    };

    requires 'Dist::Zilla';

    requires 'Dist::Zilla::Role::PluginBundle::PluginRemover';
    requires 'Dist::Zilla::Plugin::ModuleBuildTiny';
    requires 'Dist::Zilla::Plugin::CopyFilesFromBuild';
    requires 'Dist::Zilla::Plugin::VersionFromModule';
    requires 'Dist::Zilla::Plugin::Prereqs::FromCPANfile';
    requires 'Dist::Zilla::Plugin::ReadmeFromPod';
    requires 'Dist::Zilla::Plugin::Signature';

    requires 'Pod::Markdown';

    feature linux => sub {
        requires 'Archive::Tar::Wrapper';
    };

    # debugging and profiling
    requires 'Devel::NYTProf';
    suggests 'Devel::hdb';
    suggests 'Devel::Cover';

    # PAR
    requires 'PAR::Packer';
    requires 'Filter::Crypto';
};

on test => sub {
    requires 'Test::More', '0.88';
};
