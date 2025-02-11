#!/usr/bin/env perl
use Modern::Perl;
use Term::ANSIColor qw(:constants);
use Git::Wrapper;
use File::Slurp qw( write_file );
use File::Temp  qw( tempfile );
use List::Util  qw( first );
use Getopt::Long;
use Pod::Usage;
use Try::Tiny;
$Term::ANSIColor::AUTOLOCAL = 1;

my $git_dir       = '.';
my $target_branch = 'main';
my ( $new_branch, $nb_commits, $help );

GetOptions(
    'git-dir=s'       => \$git_dir,
    'target-branch=s' => \$target_branch,
    'new-branch=s'    => \$new_branch,
    'n=s'             => \$nb_commits,
    'help|?'          => \$help,
) or pod2usage(2);

pod2usage(1) if $help;

my $git = Git::Wrapper->new($git_dir);

# Check if the directory is a valid Git repo
die "'$git_dir' is not a valid Git repository.\n" unless -d "$git_dir/.git";

# Ensure the branch is clean
if ( $git->status('-uno')->is_dirty ) {
    say MAGENTA "Repository is not clean. Commit or stash your changes before rebasing.";
    exit 1;
}

# Check if the conflict resolver script exists on the target branch
my ( $conflict_resolver_script, $temp_fh )
    ;    # Keep this scope for $temp_fh, or the file will be deleted after the try block
try {
    my @tidy = $git->RUN( 'show', "$target_branch:misc/devel/tidy.pl" );
    $temp_fh                  = File::Temp->new( CLEANUP => 1 );
    $conflict_resolver_script = $temp_fh->filename;
    write_file( $conflict_resolver_script, join( "\n", @tidy ) );
} catch {
    say MAGENTA $_->error;
    if ( $_->error =~ m{fatal: path 'misc/devel/tidy\.pl'} ) {
        say RED sprintf "Conflict resolver script 'misc/devel/tidy.pl' not found on the target branch '%s'.\n",
            $target_branch;
    } else {
        say RED "Something wrong happened when retrieving the conflict resolved script from the target branch.";
    }
    exit 2;
};

my ($source_branch) = $git->RUN( 'symbolic-ref', '--short', 'HEAD' );

# Bug 38664 is "Tidy the whole codebase"
my @tidy_commits = grep { m{\|Bug 38664: } } $git->RUN( 'log', '--format=%h|%s', $target_branch );
unless (@tidy_commits) {
    say RED sprintf "The target branch (%s) does not contain the tidy commits from bug 38664.", $target_branch;
    exit 2;
}
my ($tidy_commit)        = split '\|', $tidy_commits[0];
my ($commit_before_tidy) = split '\|', $tidy_commits[-1];
$commit_before_tidy .= '^1';

# Do not do anything if we have the tidy commits in the git log
if ( $git->branch( $source_branch, '--contains', $tidy_commit ) ) {
    say GREEN "No need to rebase, your branch already contains the tidy commits!";
    exit;
}

my $tmp_src_branch = "$source_branch-tmp";
$new_branch ||= "$source_branch-rebased";

say BLUE "Creating a temporary branch '$tmp_src_branch'...";
try {
    $git->checkout( '-b', $tmp_src_branch );
} catch {
    say MAGENTA $_->error;
    say RED sprintf "Cannot create and checkout branch '%s'.", $tmp_src_branch;
    if ( $_->error =~ m{already exists} ) {
        say RED "Delete it and try again.";
        say sprintf "\t\$ git branch -D %s", $tmp_src_branch;
    }
    exit 2;
};

# Rebase the branch up to before the tidy work
unless ( $git->branch( $source_branch, '--contains', $commit_before_tidy ) ) {
    say BLUE "Rebasing the temporary branch up to before the tidy commits...";
    try {
        $git->RUN( 'rebase', $commit_before_tidy );
    } catch {
        say MAGENTA $_->error;
        say RED "Cannot rebase cleanly up to before the tidy commits";
        say RED "Continue the rebase process then try again.";
        say RED sprintf "You will need to rename your original branch (%s) and delete the temporary one (%s).",
            $source_branch, $tmp_src_branch;
        say "Possible commands are (after you fixed the conflicts):";
        say "\t\$ git rebase --continue",;
        say sprintf "\t\$ git checkout -B %s %s", $source_branch, $tmp_src_branch;
        say sprintf "\t\$ git branch -D %s", $tmp_src_branch;
        exit 2;
    };
}

# Create a new branch
say BLUE "Creating a new branch '$new_branch' starting at the end of the tidy commits...";
try {
    $git->checkout( '-b', $new_branch, $tidy_commit );
} catch {
    say MAGENTA $_->error;
    say RED sprintf "Cannot create and checkout branch '%s'.", $new_branch;
    if ( $_->error =~ m{already exists} ) {
        say RED "Delete it and try again.";
        say sprintf "\t\$ git branch -D %s", $new_branch;
    }
    exit 2;
};

# Get the list of commits from the source branch
say BLUE "Getting commit list from branch '$tmp_src_branch'...";
unless ($nb_commits) {
    say BLUE "No number of commits passed, trying to guess it...";
    my ($HEAD_commit) = $git->RUN( 'log', '--format=%s', '-n1', $tmp_src_branch );
    my $bug_number;
    if ( $HEAD_commit =~ m{^Bug\s(\d+):} ) {
        $bug_number = $1;
    }
    unless ($bug_number) {
        say RED "Number of commits not provided (see -n option) and HEAD commit does not start with 'Bug \\d+'";
        exit 2;
    }
    $nb_commits = grep { m{\|Bug\s$bug_number:} } $git->RUN( 'log', '--format=%h|%s', $tmp_src_branch );
    say GREEN sprintf "Found %s commits to process", $nb_commits;
}

# Apply each commit to the new branch
my @commits = reverse $git->RUN( 'log', '--format=%h', "$tmp_src_branch~$nb_commits..$tmp_src_branch" );
say BLUE sprintf "Processing %s commits...", scalar(@commits);
while ( my ( $i, $commit ) = each @commits ) {
    say BLUE sprintf "\tProcessing commit %s... (%s/%s)", $commit, $i + 1, scalar @commits;

    # Get the list of modified files in this commit
    my @modified_files = $git->diff_tree( '--no-commit-id', '--name-only', '-r', $commit );
FILE: while ( my ( $ii, $file ) = each @modified_files ) {
        say BLUE sprintf "\t\tProcessing file %s... (%s/%s)", $file, $ii + 1, scalar @modified_files;

        # Retrieve the content of the file from this commit
        my @content = try {
            $git->RUN( "show", "$commit:$file" );
        } catch {
            if ( $_->error =~ m{fatal: path '.*' exists on disk, but not in '$commit'} ) {
                say BLUE "\t\t\tFile does not exist, removing...";
                $git->rm($file);
            } else {
                say RED "Something wrong happened when retrieving the file from the branch.";
                exit 2;
            }
        };

        next unless @content;    # We removed the file

        write_file( $file, join "\n", @content );

        # Tidy the file
        my $cmd = "$conflict_resolver_script $file";
        try {
            system $cmd;
        } catch {
            say RED "Cannot tidy $file: $_";
            exit 2;
        };
    }

    # Stage the changes
    $git->add($_) for @modified_files;

    # Get the original commit information
    my ( $author, $date, $message ) = get_commit_info($commit);

    # Commit the changes with the original metadata
    say BLUE "\t\tCommitting changes...";
    my @new_commit = $git->commit(
        '--no-verify',
        '--author' => $author,
        '--date'   => $date,
        '-m'       => $message
    );
}

say GREEN "\nAll commits from the source branch have been applied to '$new_branch'!\n";

try {
    say BLUE sprintf "\nRebasing on top of %s...", $target_branch;
    $git->RUN( 'rebase', $target_branch );
} catch {
    say MAGENTA $_->error;
    say RED "Cannot rebase cleanly";
    say BLUE "You can continue the rebase process without the need of this script.";
    exit 2;
};

say GREEN "Everything applied successfully!";
exit 0;

sub get_commit_info {
    my ($commit) = @_;
    my ($author) = $git->show( '--format=%an <%ae>', '--no-patch', $commit );
    my ($date)   = $git->show( '--format=%ai',       '--no-patch', $commit );
    my $message  = join "\n", $git->show( '--format=%B', '--no-patch', $commit );
    return ( $author, $date, $message );
}

=head1 NAME

auto_rebase.pl - Automate rebasing and resolving conflicts during Git rebases.

=head1 SYNOPSIS

auto_rebase.pl [options]

 Options:
   --git-dir         Path to the Git repository (default: current directory)
   --target-branch   Target branch to rebase onto (default: main)
   --new-branch      The resulting branch (default: ${source-branch}-rebased)
   -n                The number of commits to pick for rebase from the source branch
   --help            Show this help message

=head1 DESCRIPTION

This script automates the rebasing of a Git branch onto a target branch that contains the tidy version of the codebase. It rebases up to before the first commit of the tidy commits then applies the commits from the source branch, tidy this version and commits.

Finally the rebase will continue.

The source branch is the branch that is currently checked out.

=head1 EXAMPLES

Rebase onto 'main' in the current repository:

  ./auto_rebase.pl

Rebase onto 'dev' in a specified Git repository:

  ./auto_rebase.pl --git-dir /path/to/repo --target-branch dev

Rebase onto 'main' and produces a new branch named 'new-branch'

  ./auto_rebase.pl --new-branch new-branch

Rebase onto 'main' the last 42 commits of the current branch

  ./auto_rebase.pl -n 42

=head1 AUTHOR

Jonathan Druart <jonathan.druart@bugs.koha-community.org>

=cut
