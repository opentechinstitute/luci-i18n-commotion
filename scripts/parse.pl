#!/usr/bin/perl -w
use strict;

# To do: Fix use vs. require
use Data::Dumper;
use Git::Repository;
use File::Path qw(make_path remove_tree);
use File::Next;
use Text::Balanced qw(extract_bracketed extract_delimited extract_tagged);
use File::Copy;
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
my $working_translations_file = $working_translations_dir . 'working.commotion-luci-en.po';

if (-e '../translations/commotion-luci-en.po') {
	rename '../commotion-luci-en.po' $working_translations_file;
} else {
	system("touch $working_translations_file");
}

# Traverse source directories, identifying translatable text
my @working_files;
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
	push(@working_files, $file);
}

##
## Separate text strings from translation tags
##
## string parsing functions from luci.subsignal.org
## http://luci.subsignal.org/trac/browser/luci/trunk/build/i18n-scan.pl
## copyright 2013 by jow 

# looks like stringtable is a hash so it can handle multi-line strings
my %stringtable;

foreach my $file (@working_files) {
	chomp $file;
	if( open S, "< $file" ) {
		local $/ = undef;
		my $raw = <S>;
		close S;

		my $text = $raw;

		while( $text =~ s/ ^ .*? (?:translate|translatef|i18n|_) [\n\s]* \( /(/sgx ) {
			( my $code, $text ) = extract_bracketed($text, q{('")});
			$code =~ s/\\\n/ /g;
			$code =~ s/^\([\n\s]*//;
			$code =~ s/[\n\s]*\)$//;

			my $res = "";
			my $sub = "";

			if( $code =~ /^['"]/ ) {
				while( defined $sub ) {
					( $sub, $code ) = extract_delimited($code, q{'"}, q{\s*(?:\.\.\s*)?});

					if( defined $sub && length($sub) > 2 ) {
						$res .= substr $sub, 1, length($sub) - 2;
					} else {
						undef $sub;
					}
				}
			} elsif( $code =~ /^(\[=*\[)/ ) {
				my $stag = quotemeta $1;
				my $etag = $stag;
				$etag =~ s/\[/]/g;

				( $res ) = extract_tagged($code, $stag, $etag);

				$res =~ s/^$stag//;
				$res =~ s/$etag$//;
			}

			$res = dec_lua_str($res);
			$stringtable{$res}++ if $res;
		}

		$text = $raw;

		while( $text =~ s/ ^ .*? <% -? [:_] /<%/sgx ) {
			( my $code, $text ) = extract_tagged($text, '<%', '%>');

			if( defined $code ) {
				$code = dec_tpl_str(substr $code, 2, length($code) - 4);
				$stringtable{$code}++;
			}
		}
	}
}


# Create new PO file
my $new_strings_file = $working_translations_dir . 'new_strings.txt';
unless (-e $working_translations_file) {
	$working_translations_file = $new_strings_file;
}
my $working_strings; {
	# To do: this section needs work
	local $/ = undef;
	open (WS, "<", $working_translations_file);
	$working_strings = <WS>;
	close(WS);

	# Strings contained in %stringtable
	# Compare strings to stable PO file
	open (WF, ">>", $working_translations_file);
	foreach my $key ( sort keys %stringtable ) {
		# Discard matching strings
		# Add new/modified strings to working PO file
		$key =~ s/"/\\"/g;
		if ($working_strings !~ m/$key/ ) {
			if( length $key ) {
				printf WF "msgid \"%s\"\nmsgstr \"\"\n\n", $key;
			}
		}
	}
}



# Commit working PO file

# Upload to Transifex/GitHub


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

