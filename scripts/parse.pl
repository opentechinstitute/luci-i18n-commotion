#!/usr/bin/perl -w
use strict;

use Data::Dumper;
use Git::Repository; 
use File::Path qw(make_path remove_tree);
use File::Next;
#use Text::Balanced
#use File::Find::Rule;
# App::Ack not designed to be used programmatically
# The file finding part is pretty simple to do. It's just calls to an iterator from File::Next.

##
## Git Info
##
my $git_account = 'https://github.com/opentechinstitute/';
my @repos = qw(commotion-openwrt commotion-feed avahi-client luci-commotion-apps 
	commotion-dashboard-helper commotion-debug-helper commotiond 
	luci-commotion-quickstart luci-commotion-splash luci-commotion luci-theme-commotion
);
my $working_dir = 'working/';
my $working_source_dir = $working_dir . 'source/';
my $working_translations_dir = $working_dir . 'translations/';


##
## Translation files
## 
my $po_dir = '../'; # Location of translation files
my %translate_flags = (
	'translate(' => ')',
	'<%:' => '%>'
);


# Prepare working directory
if (not -e $working_dir) {
	print("Creating working directories\n");
	make_path($working_dir, $working_source_dir, $working_translations_dir, {verbose=>1})
		|| die "ERROR: Couldn't create " . $working_dir . "\n";	
}

# Update code repos
foreach my $repo (@repos) {
	if (not -e $working_source_dir . $repo) {
		my $origin = $git_account . $repo;
		print("Cloning " . $origin . " into " . $working_source_dir ."\n");
		Git::Repository->run( clone => $origin => $working_source_dir . $repo)
			|| warn "Couldn't clone " . $origin . "\n";
	} else {
		print("Updating " . $repo . "\n");
		my $r = Git::Repository->new( work_tree => $working_source_dir . $repo, { quiet => 1 });
		$r->command(pull => 'origin', 'master') || warn "Couldn't pull remotes\n";
	}
}

# Fetch most recent PO files
## To Do: Add Transifex details
print("Updating translation files\n");
my $r = Git::Repository->new ( work_tree => $po_dir, { quiet => 1 });
$r->command(pull =>'--rebase', 'origin', 'master') || warn "Couldn't pull stable branch\n";

# Create working PO file from stable PO file
### To do: Find a better way to do this
### To do: Create .po headers
if (-e '../translations/commotion-luci-en.po') {
	system("cp ../commotion-luci-en.po $working_translations_dir/working.commotion-luci-en.po")
}

# Traverse source directories, identifying translatable text
my @working_files;
##
## File Scan Options
##
my $descend_filter = sub { $_ ne '.git' };
my $file_filter = sub { $_ !~ /.git/ && $_ !~ /.jpg/ && $_ !~ /.png/ && $_ !~ /.gif/};
my $scan = File::Next::files( {
	descend_filter => $descend_filter,
	file_filter => $file_filter,
	error_handler => sub { my $msg = shift; warn($msg) },
	},
	$working_source_dir);
while (defined(my $file = $scan->())) {
	push(@working_files, $file);
}

# Separate text strings from translation tags
## use Text::Balanced::extract_tagged
# Create new PO file

# Compare strings to stable PO file
## Discard matching strings
## Add new/modified strings to working PO file

# Commit working PO file

# Upload to Transifex/GitHub
