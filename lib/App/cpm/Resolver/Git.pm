package App::cpm::Resolver::Git;
use strict;
use warnings;
use App::cpm::Git;
use App::cpm::version;

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

sub fetch_rev {
    my ($class, $uri, $ref) = @_;
    return unless $ref;

    ($uri) = App::cpm::Git->split_uri($uri);
    my ($rev, $version) = `git ls-remote --refs $uri $ref` =~ /^(\p{IsXDigit}{40})\s+(?:refs\/tags\/(v?\d+\.\d+(?:\.\d+)?)$)?/;
    $rev = $ref if !$rev && $ref =~ /^[0-9a-fA-F]{4,}$/;
    return ($rev, $version);
}

sub resolve {
    my ($self, $job) = @_;

    my $is_git_source = ($job->{source} && $job->{source} eq 'git');

    my $job_options = $job->{options};
    if (exists $job_options->{git} && !$is_git_source) {
        $job->{uri} = $job_options->{git} if exists $job_options->{git};
        $job->{ref} = $job_options->{ref} if exists $job_options->{ref};
        $job->{provides} = [{package => $job->{package}}];
        $job->{source} = 'git';
        $is_git_source = 1;
    }

    return {error => 'Not a git dependency'} unless $is_git_source;

    my ($rev, $version);
    if ($job->{ref}) {
        ($rev, $version) = $self->fetch_rev($job->{uri}, $job->{ref});
    } else {
        my %tags;
        my ($uri) = App::cpm::Git->split_uri($job->{uri});

        # todo for all the `ls-remote` commands: lookup cpm cache before remote lookup
        my $out = `git ls-remote --tags $uri "*.*"`;
        while ($out =~ /^(\p{IsXDigit}{40})\s+refs\/tags\/(.+?)(\^\{\})?$/mg) {
            my ($r, $v, $o) = ($1, $2, $3);
            $tags{$v} = $r if !$tags{$v} || $o;
        }
        if (%tags) {
            use version;
            my @tags = map +{
                version => App::cpm::version->parse($_),
                rev     => $tags{$_},
            }, grep {version::is_lax($_)} keys %tags;
            foreach my $tag (sort { $b->{version} <=> $a->{version} } @tags) {
                if ($tag->{version}->satisfy($job->{version_range})) {
                    $version = $tag->{version}->stringify;
                    $rev = $tag->{rev};
                    last;
                }
            }
        } else {
            ($rev) = `git ls-remote $uri HEAD` =~ /^(\p{IsXDigit}+)\s/;
        }
    }
    return { stop => 1, error => 'repo (`' . $job->{uri} . '`) or ref (`' . ($job->{ref}||'master') . '`) not found' } unless $rev;

    return {
        source => 'git',
        uri => $job->{uri},
        ref => $job->{ref},
        rev => $rev,
        package => $job->{package},
        version => $version,
    };
}

1;
