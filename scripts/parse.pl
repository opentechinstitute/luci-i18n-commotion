#!/usr/bin/perl -w
use strict;
my $testing = 1;
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

##
## Git Info
##
my $git_account = 'https://github.com/opentechinstitute/';
my @repos = qw(commotion-openwrt commotion-feed avahi-client luci-commotion-apps 
	commotion-dashboard-helper commotion-debug-helper commotiond 
	luci-commotion-quickstart luci-commotion-splash luci-commotion luci-theme-commotion
);


##
## Directory Structure
##
my $working_dir = 'working/';
my $working_source_dir = $working_dir . 'source/';
my $working_translations_dir = $working_dir . 'translations/';

my $stable_dir = '../';
my $stable_translations_dir = $stable_dir . 'translations/';

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
push(@todo, "add transifex github integration");
print("Updating translation files\n");
my $r = Git::Repository->new ( work_tree => $stable_dir, { quiet => 1 });
$r->command(pull =>'--rebase', 'origin', 'master') || warn "Couldn't pull stable branch\n";

##
## Translation files
## 
my @stable_po_files;
my @working_po_files;
if ($testing == 1) {
	print "Limiting scope of operations!\n";
	@stable_po_files = ($stable_translations_dir.'commotion-luci-en.po', $stable_translations_dir.'commotion-luci-ar.po');
} else {
	opendir(DIR, $stable_translations_dir) or warn "Couldn't open stable po dir: $!";
	@stable_po_files = readdir(DIR); 
	closedir(DIR);
}

# Create working PO file from stable PO file
if (@stable_po_files) {
	foreach (@stable_po_files) {
		my $stable_po_file = $_;
		my $working_po_file = $_;
		$working_po_file =~ s|$stable_translations_dir||;
		$working_po_file = $working_translations_dir . 'working.' . $working_po_file;
		push(@working_po_files, $working_po_file);
		copy($stable_po_file, $working_po_file) || die "Couldn't copy PO file: $!\n";
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

# looks like stringtable is a hash so it can handle multi-line strings
my %stringtable;
foreach my $file (@working_source_files) {
	chomp $file;
# read file into $raw
	if( open S, "< $file" ) {
		local $/ = undef;
		my $raw = <S>;
		close S;

# copy $raw to $text for manipulation
		my $text = $raw;

# search $text for translate flags
		while( $text =~ s/ ^ .*? (?:translate|translatef|i18n|_) [\n\s]* \( /(/sgx ) {
# separate usable $code from $text. $code and $text reverse of expected
			( my $code, $text ) = extract_bracketed($text, q{('")});
# strip newlines and extra whitespace out of $code
			$code =~ s/\\\n/ /g;
			$code =~ s/^\([\n\s]*//;
			$code =~ s/[\n\s]*\)$//;

			my $res = "";
			my $sub = "";

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
# add $res to %stringtable
			if ($res) {
				push(@{ $stringtable{$file} }, $res);
			}
		}

		$text = $raw;
# Same steps for lua code
		while( $text =~ s/ ^ .*? <% -? [:_] /<%/sgx ) {
			( my $code, $text ) = extract_tagged($text, '<%', '%>');

			if( defined $code ) {
				$code = dec_tpl_str(substr $code, 2, length($code) - 4);
				push(@{ $stringtable{$file} }, $code);
			}
		}
	}
}

foreach my $working_po_file (@working_po_files) { 
	my $translations = ();
	# English file can be overwritten each time

	# NOTE: we don't care about anything but msgid changes
	# and existence of previous translations

	# Generate id:str pairs for PO files
	# NOTE: translations is a hash ref
	unless ($working_po_file =~ m|-en.po$|) {
		$translations = &Get_Translations($working_po_file);
	}

	# Write File
	print "Writing to $working_po_file\n";
	&Write_PO_File($working_po_file, \%stringtable, $translations);
}

# Commit working PO file
# rewrite file array as hash
# associate stable => working
# reverse hash to copy working to stable
#my %rhash = reverse %hash; my $key = $rhash{$value}; 

# Upload to Transifex/GitHub
#http://support.transifex.com/customer/portal/topics/440186-api/articles

push(@todo, "Move common functions to subroutines");
# print to do list
if ($testing == 1) { foreach (@todo) { print "$_\n"; } }

exit 0; 

sub Get_Translations {
	my $working_po_file = pop(@_);
	print "Getting translations for $working_po_file\n";
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

sub Write_PO_File {
	# NOTE: stringtable and translations are hash references
	my ($working_po_file, $stringtable, $translations) = @_;
=pot
	if ($working_po_file =~ m|-en.po$|) {
		print "skipping english file\n";
		return;
	} 
=cut
	# Generate headers, 
	my @po_header = &_Generate_PO_Header($working_po_file);

#
# Extra table created to keep hashes in scope
# This can probably be moved to a subroutine
#
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

	open(WPO, "> $working_po_file") || die "Couldn't open $working_po_file: $!\n";
	foreach (@po_header) {
		print WPO $_,"\n";
	}
	foreach (@wps) {
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

sub _Generate_PO_Header {
	my $working_po_file = pop;	
	my @po_header;
	my $dt = DateTime->now();
	my $date = $dt.'\n"';
	#my $date = strftime "%Y-%m-%d %R\n";
	#"PO-Revision-Date: 2013-08-16 20:50+0000\n"
	open(WPF, "< $working_po_file");
	while(<WPF>) {
		chomp;
		if ($_ =~ m|^\"PO-Revision-Date\:\ |) {
			$_ = $& . $date;
		}
		push(@po_header, $_);
		last if ($_ =~ m|^"Plural|);
	}
	close(WPF);
	return(@po_header);
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
