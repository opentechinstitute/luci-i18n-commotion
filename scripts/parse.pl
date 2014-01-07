#!/usr/bin/perl -w

###
### First pass at an automated PO file generator
### This script is in need of major refactoring
### Contains lots of duplicate code and fast workarounds
### Also needs a solution to git integration of generated files
###

use strict;
my $verbosity = 1;
my @todo = ("\n\nTo Do:");
push(@todo, "add copyright notice");
push(@todo, "Fix use vs. require");
use Data::Dumper;
use File::Path qw(make_path remove_tree);
use Git::Repository;
use File::Copy;
use File::Next;
use Text::Balanced qw(extract_bracketed extract_delimited extract_tagged);
use Text::Diff;
use DateTime;

## TODO: for next major revision:
## Look for ways to minimize string overlap
## http://www.perlmonks.org/?node_id=816086
push(@todo, "minimize duplicate strings in po files - http://www.perlmonks.org/?node_id=816086");
push(@todo, "use repo objects");
##
## Repos to be scanned for translatable strings
##
my %repos = (
	'luci-commotion-apps' => {
		'source' => 'https://github.com/opentechinstitute/luci-commotion-apps.git',
		'branch' => 'master',
	},
	
	'luci-theme-commotion' => {
		'source' => 'https://github.com/opentechinstitute/luci-theme-commotion.git',
		'branch' => 'master',
	},
	'luci-commotion' => {
		'source' => 'https://github.com/opentechinstitute/luci-commotion.git',
		'branch' => 'master',
	},
	'commotion-dashboard-helper' => {
		'source' => 'https://github.com/opentechinstitute/commotion-dashboard-helper.git',
		'branch' => 'master',
	}, 
	'commotiond commotion-service-manager' => {
		'source' => 'https://github.com/opentechinstitute/commotion-service-manager.git',
		'branch' => 'master',
	},
	'commotion-router' => {
		'source' => 'https://github.com/opentechinstitute/commotion-router.git',
		'branch' => 'master',
	},
	'commotion-feed' => {
		'source' => 'https://github.com/opentechinstitute/commotion-feed.git',
		'branch' => 'master',
	}, 
	'commotion-lua-helpers' => {
		'source' => 'https://github.com/opentechinstitute/commotion-lua-helpers.git',
		'branch' => 'master',
	},
	'serval-dna' => {
		'source' => 'https://github.com/opentechinstitute/commotion-dashboard-helper.git',
		'branch' => 'commotion-wireless',
	},
	'luci-commotion-splash' => {
		'source' => 'https://github.com/opentechinstitute/luci-commotion-splash.git',
		'branch' => 'master',
	},
	'commotion-debug-helper' => {
		'source' => 'https://github.com/opentechinstitute/commotion-debug-helper.git',
		'branch' => 'master',
	},
	'luci-i18n-commotion' => {
		'source' => 'https://github.com/opentechinstitute/luci-i18n-commotion.git',
		'branch' => 'master',
	}, 
	'olsrd' => {
		'source' => 'https://github.com/opentechinstitute/olsrd.git',
		'branch' => 'master',
	},
);

##
## Directory Structure
##
my $working_dir = 'working/';
my $working_source_dir = $working_dir . 'source/';
my $working_translations_dir = $working_dir . 'translations/';
my $stable_translations_dir = $working_source_dir . 'luci-i18n-commotion/translations/';

# Prepare working directory
if (not -e $working_dir) {
	print("Creating working directories\n");
	make_path($working_dir, $working_source_dir, $working_translations_dir, {verbose=>1})
		|| die "ERROR: Couldn't create " . $working_dir . "\n";	
}

# Iterate over commotion-router packages defined in %repos
# If working copy does not exist, clone it and check out proper branch
# If working copy does exist, check out proper branch and pull updates
foreach my $repo (keys %repos) {
	if (not -e $working_source_dir . $repo) {
		print("Cloning " . $repo . " into " . $working_source_dir ."\n");
		Git::Repository->run( clone => $repos{$repo}{'source'} => $working_source_dir . $repo)
			|| warn "Couldn't clone " . $repos{$repo}{'source'} . "\n";
		my $r = Git::Repository->new( work_tree => $working_source_dir . $repo);
		print("\tChecking out $repos{$repo}{'branch'} branch\n");
		$r->command(checkout => $repos{$repo}{'branch'}) || die "Couldn't check out proper branch\n";
	} else {
		print("Updating " . $repo . "\n");
		my $r = Git::Repository->new( work_tree => $working_source_dir . $repo);
		$r->command(checkout => $repos{$repo}{'branch'}) || die "Couldn't check out proper branch\n";
		$r->command(pull => 'origin', $repos{$repo}{'branch'}, { quiet => 1 }) || warn "Couldn't pull remotes\n";
	}
}

push(@todo, "add transifex github integration");

##
## Translation files
## 

opendir(DIR, $stable_translations_dir) or warn "Couldn't open stable po dir: $!";
my @po_files = glob "$stable_translations_dir*.po"; 
closedir(DIR);

for (0..$#po_files){
	$po_files[$_] =~ s/^$stable_translations_dir//;
}

# Create working PO file from stable PO file
if (@po_files) {
	foreach (@po_files) {
		if ($verbosity == 1) { print("Copying $_ to $working_translations_dir\n"); }
		copy($stable_translations_dir . $_, $working_translations_dir . $_) || die "Couldn't copy PO file $_: $!\n";
	}
} else {
	warn "Couldn't find any stable PO files!\n";
}

# Traverse source directories, identifying translatable text
my @working_source_files;
##
## File Scan Options
##
my $descend_filter = sub { $_ ne '.git' };
my $file_filter = sub { $_ =~ '.htm' or $_ =~ '.lua' };
my $scan = File::Next::files( {
	descend_filter => $descend_filter,
	file_filter => $file_filter,
	error_handler => sub { my $msg = shift; warn($msg) },
	},
	$working_source_dir);
while (defined(my $file = $scan->())) {
	push(@working_source_files, $file);
}

##
## Separate text strings from translation tags
##
## string parsing functions from luci.subsignal.org
## http://luci.subsignal.org/trac/browser/luci/trunk/build/i18n-scan.pl
## copyright 2013 by jow 

my %stringtable;
foreach my $file (@working_source_files) {
	chomp $file;
	if ($verbosity == 1) { print "Populating string table from $file\n"; }
	# read file into $raw
	if( open S, "< $file" ) {
		local $/ = undef;
		my $raw = <S>;
		close S;

		my @res = Extract_Translations($raw);
		if (@res) {
			push(@{ $stringtable{$file} }, @res);
		}
		my @code = Extract_Lua_Translations($raw);
		if (@code) {
			push(@{ $stringtable{$file} }, @code);
		}
	}
}

foreach my $po_file (@po_files) { 
	if ($verbosity == 1) { print "Salvaging translations from $po_file\n"; }
	my $translations = ();
	# English file can be overwritten each time

	# NOTE: we don't care about anything but msgid changes
	# and existence of previous translations

	# Generate id:str pairs for PO files
	# NOTE: translations is a hash ref
	unless ($po_file =~ m|-en.po$|) {
		$translations = Fetch_Translations($working_translations_dir . $po_file);
	}
	
	if ($verbosity == 1) { print "Generating file header for $po_file\n"; }
	my @po_header = _Generate_PO_Header($working_translations_dir . $po_file);
	
	if ($verbosity == 1) { print "Generating file body for $po_file\n"; }
	my @po_body = _Generate_PO_Body($working_translations_dir . $po_file, \%stringtable, $translations);
	
	# Write File
	print "Writing to $working_translations_dir$po_file\n";
	Write_PO_File($working_translations_dir . $po_file, \@po_header, \@po_body);
}

# Do this manually until trial period is complete
## Copy working po files back to stable
#%po_files = reverse %po_files;
#for my $working (keys %po_files) {
#	print "Copying working po file to $po_files{$working}\n";
#	copy($working, $po_files{$working}) || die "Couldn't copy po file to stable directory: $!\n";
#}

# Commit new PO files and upload to github
#my $i18n_r = Git::Repository->new ( work_tree => $stable_dir, { quiet => 1 });
#$i18n_r->command(pull =>'--rebase', 'origin', 'master') || warn "Couldn't pull stable branch\n";
#my @command = (
#	"add => '$working_translations_dir'",
#	"commit => '-m', 'Quarterly Commotion UI strings update'",
#	"push, '$i18n_remote', '$i18n_branch'",
#);

## For some reason git doesn't recognize add when run as a loop
#foreach my $cmd (@command) {
#	if ($verbosity == 1) {
#		$cmd = $cmd . ', --dry-run';
#	}
#	$i18n_r->command($cmd) || die "Couldn't run git command: $!";
#}
#$i18n_r->run(add => "$working_translations_dir");
#$i18n_r->run(commit => 'm', 'Quarterly Commotion UI strings update');
#$i18n_r->run(push => "$i18n_remote", "$i18n_branch");


# Upload to Transifex/GitHub
#http://support.transifex.com/customer/portal/topics/440186-api/articles

push(@todo, "Move common functions to subroutines");
# print to do list
if ($verbosity == 1) { foreach (@todo) { print "$_\n"; } }

exit 0;

sub Extract_Translations {
	my $text = pop(@_);
	my @res = ();
	my $res = "";
	my $sub = "";
	# search $text for translate flags
	while( $text =~ s/ ^ .*? (?:translate|translatef|i18n|_) [\n\s]* \( /(/sgx ) {
		# separate usable $code from $text. $code and $text reverse of expected
		( my $code, $text ) = extract_bracketed($text, q{('")});
		# strip newlines and extra whitespace out of $code
		$code =~ s/\\\n/ /g;
		$code =~ s/^\([\n\s]*//;
		$code =~ s/[\n\s]*\)$//;



		# Check code for quoted text. Store in $sub
		if( $code =~ /^['"]/ ) {
			while( defined $sub ) {
				( $sub, $code ) = extract_delimited($code, q{'"}, q{\s*(?:\.\.\s*)?});

				if( defined $sub && length($sub) > 2 ) {
					# use sub to build $res
					$res .= substr $sub, 1, length($sub) - 2;
				} else {
					undef $sub;
				}
			}
		# Check code for tagged text. store in $res
		} elsif( $code =~ /^(\[=*\[)/ ) {
			my $stag = quotemeta $1;
			my $etag = $stag;
			$etag =~ s/\[/]/g;

			( $res ) = extract_tagged($code, $stag, $etag);

			$res =~ s/^$stag//;
			$res =~ s/$etag$//;
		}

		# Strip superfluous strings out of $res
		$res = dec_lua_str($res);
		if ($res) {
			push(@res, $res);
		}
		# add $res to %stringtable
	}
	@res = uniq(@res);
	return(@res);
}

sub Extract_Lua_Translations {
	my $text = pop(@_);
	my @code;
	while( $text =~ s/ ^ .*? <% -? [:_] /<%/sgx ) {
		( my $code, $text ) = extract_tagged($text, '<%', '%>');

		if( defined $code ) {
			$code = dec_tpl_str(substr $code, 2, length($code) - 4);
		}
		push(@code, $code);
	}
	@code = uniq(@code);
	return(@code);
}

sub Fetch_Translations {
	my $working_po_file = pop(@_);
	if ($verbosity == 1) { print "Getting translations for $working_po_file\n"; }
	my %translations;
	open(WPO, "< $working_po_file") || die "Couldn't open translation file: $!\n";
	my @wpo = <WPO>;
	close(WPO);
	for (my $i = 0; $i < $#wpo; $i++) {
		local $/ = "";
		chomp($wpo[$i]);
		if ($wpo[$i] =~ m|^msgid|) {
			my $mid = $wpo[$i];
			unless ($wpo[$i+1] =~ m|^msgstr|) {
				$mid = $mid . $wpo[$i+1];
			} else {
				my $mstr = $wpo[$i+1];
				# quote removal might be better with extract
				$mid =~ s|^msgid "?||;
				$mid =~ s|"?$||;
				$mstr =~ s|^msgstr "?||;
				$mstr =~ s|"?$||;
				chomp($mstr);
				$translations{$mid} = $mstr;
			}
		}
		
	}
	return \%translations;
}

sub _Generate_PO_Header {
	my $working_po_file = pop;	
	my @po_header;
	my $dt = DateTime->now();
	$dt = $dt.'\n"';
	#my $date = strftime "%Y-%m-%d %R\n";
	#"PO-Revision-Date: 2013-08-16 20:50+0000\n"
	open(WPF, "< $working_po_file");
	while(<WPF>) {
		chomp;
		if ($_ =~ m|^\"PO-Revision-Date\:\ |) {
			$_ = $& . $dt;
		}
		push(@po_header, $_);
		last if ($_ =~ m|^"Plural|);
	}
	close(WPF);
	return(@po_header);
}

sub _Generate_PO_Body {
	my ($working_po_file, $stringtable, $translations) = @_;
	my @wps = ();
	# Get k:v else write k:msgstr
	foreach my $f (keys %{$stringtable}) {
		chomp($f);
		push(@wps, "#: $f");
		foreach my $id ( @{$stringtable->{$f}} ) {
			my $str;
			if ($working_po_file =~ m|-en.po$|) {
				$str = 'msgstr "' . $id . '"';
			} else {
				# need to do better string extraction
				if ( exists $translations->{$id} ) {
					$str = 'msgstr "' . $translations->{$id} . '"';
				} else {
					$str = 'msgstr ""';
				}
			}
			my $mid = 'msgid "' . $id . '"';
			push(@wps, $mid);
			push(@wps, $str);
		}
		push(@wps, "\n");
	}

	return(@wps);
}

sub Write_PO_File {
	# NOTE: po_header and po_body are array references
	my ($working_po_file, $po_header, $po_body) = @_;

	open(WPO, "> $working_po_file") || die "Couldn't open $working_po_file: $!\n";
	foreach (@{$po_header}) {
		print WPO $_,"\n";
	}
	foreach (@{$po_body}) {
		print WPO $_,"\n";
	}
	close(WPO);
	return;
}
##
## Translation tags
##
sub dec_lua_str
{
        my $s = shift;
        $s =~ s/[\s\n]+/ /g;
        $s =~ s/\\n/\n/g;
        $s =~ s/\\t/\t/g;
        $s =~ s/\\(.)/$1/g;
        $s =~ s/^ //;
        $s =~ s/ $//;
        return $s;
}

sub dec_tpl_str
{
        my $s = shift;
        $s =~ s/-$//;
        $s =~ s/[\s\n]+/ /g;
        $s =~ s/^ //;
        $s =~ s/ $//;
        $s =~ s/\\/\\\\/g;
        return $s;
}


sub uniq {
    my %seen = ();
    my @r = ();
    foreach my $a (@_) {
        unless ($seen{$a}) {
            push @r, $a;
            $seen{$a} = 1;
        }
    }
    return @r;
}
