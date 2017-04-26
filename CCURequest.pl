#!/usr/bin/perl

# Copyright 2005-2008 Akamai Technologies, Inc.
# The information herein is proprietary and confidential to Akamai,
# and it may only be used under appropriate agreements with the
# Company.  Access to this information does not imply or grant you any
# right to use the information, all such rights being expressly
# reserved.

# This example, CCURequest.pl, allows you to enter a username,
# password, e-mail address for notification, 
# the domain (production or staging) as well as a file that
# contains a list of ARLs/URLs on the command line.

# The CCUAPI WSDL file can be obtained from http://ccuapi.akamai.com/ccuapi.wsdl

# This example does not use the WSDL service description in realtime
# (that is to say with the ->service() call) because the CCUAPI wsdl
# file contains complex types that cause versions of SOAP::Lite after
# 0.60 to use c-gensym names in the soap envelope.  This causes the
# purgeRequest call to fail.  You can still use the WSDL file to
# generate stubs successfully but SOAP::Data calls are required to
# properly name the elements.

sub usage()
{
    print "\n";
    print "Usage:\n";
    print "\n";
    print "perl CCURequest.pl --user <user> --pwd <password> --file <filename>\n";
    print "                  [--email <email>]\n";
    print "                  [--type arl|cpcode]\n";
    print "                  [--action invalidate|remove]\n";
    print "                  [--domain production|staging]\n";
    print "\n";
    print "- User, password, and file are required.\n";
    print "  The specified file should contain a list of URLs (or CP codes) to be purged.\n";
    print "\n";
    print "- Email, type, action, and domain are optional.\n";
    print "  If an email address is specified, a notification will be sent to that address.\n";
    print "  The default for type is arl.\n";
    print "  The default for action is invalidate.\n";
    print "  The default for domain is production.\n";
    print "\n";
    print "- Examples:\n";
    print "    perl CCURequest.pl --user ccuuser --pwd ccupwd --file /etc/urls --email ccuadmin\@foo.com\n";
    print "    perl CCURequest.pl --user ccuuser --pwd ccupwd --file c:\\etc\\cpcodes.txt --type cpcode --domain staging\n";
    print "\n";
}

use strict;
use Getopt::Long;
use Text::Tabs;
use Digest::MD5 qw(md5_base64);
use SOAP::Lite;

my $soap_version = SOAP::Lite->VERSION;

print "Using SOAP::Lite version: $soap_version\n";

my $soap = SOAP::Lite->new(proxy => 'https://ccuapi.akamai.com:443/soap/servlet/soap/purge',
                           uri => 'http://ccuapi.akamai.com/purge');

# -------------------------------
# Define global variables
# -------------------------------
my $debug = 0;
my $help = 0;
my ($user, $pwd, $file, $type, $action, $email, $domain, $retval, $key, $val)="";
my (@urls, @options);
my $results=""; # This will hold the purge results:
        #       uriIndex, estTime, resultMsg, modifiers, resultCode, sessionID
my $network = "ff";

# --------------------------------------
# Show usage if no arguments were given
# --------------------------------------
if (!@ARGV) {
    usage();
    exit(0);
}

# -------------------------------
# Get inputs:
#       - user/password
#       - input file
#       - email, type, action if specified
# -------------------------------
$retval = &GetOptions("user=s",\$user,
                      "pwd=s", \$pwd,
                      "file=s", \$file,
                      "email=s", \$email,
                      "domain=s", \$domain,
                      "type=s", \$type,
                      "action=s", \$action,
                      "debug", \$debug,
                      "help", \$help);

if ($help) {
    usage();
    exit(0);
}

print "\nARGUMENTS: User: $user; Pwd: $pwd; File: $file; Type: $type; Action: $action; Email: $email; Domain: $domain\n\n" if $debug;

# -------------------------------
# Validate required arguments
# -------------------------------
if (!$user || !$pwd || !$file) {
    print "\nERROR: User, password, and filename are required arguments!\n";
    usage();
    exit(1);
}

# -------------
# Set @options
# -------------
sub add_option {
    my $option = shift;
    print "option: $option\n" if $option and $debug;
    push @options, SOAP::Data->type('string')->value("$option");
}

if ($email) {
    add_option("email-notification=$email");
}

if ($domain) {
    if ($domain eq "production" or $domain eq "staging") {
        add_option("domain=$domain");
    } else {
        print "\nERROR: Invalid domain option: $domain.\n\n";
        exit(1);
    }
}

if ($type) {
    if ($type eq "cpcode" or $type eq "arl") {
        add_option("type=$type");
    } else {
        print "\nERROR: Invalid type option: $type.\n\n";
        exit(1);
    }
}

if ($action) {
    if ($action eq "invalidate" or $action eq "remove") {
        add_option("action=$action");
    } else {
        print "\nERROR: Invalid action option: $action.\n\n";
        exit(1);
    }
}

# This terminates this list of options and insures the options array is not null
add_option("");

# -------------------------------
# Get URLs from input file
# -------------------------------
open(FILE, $file) || die "Cannot open: $!\n";
my $cnt=0;
print "Reading URLs ...\n";
while (<FILE>) {
    chomp;
    print "$cnt: $_\n";
    my $soap_data = SOAP::Data->type('string')->value($_);
    push(@urls,$soap_data);
    $cnt++;
}
close(FILE);


# -------------------------------
# Call purgeRequest
# -------------------------------
$results = $soap->purgeRequest(SOAP::Data->name("name" => $user),
                               SOAP::Data->name("pwd" => $pwd),
                               SOAP::Data->name("network" => $network),
                               SOAP::Data->name("opt" => [@options]),
                               SOAP::Data->name("uri" => [@urls]));

print "\nRESULTS:\n";
while (($key,$val)=each %{$results->result()}) {
        print $key, ": ", $val, "\n";
}

