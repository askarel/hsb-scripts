<?php
#
# Concierge for Hackerspace Brussels - Web front-end - common functions
# (c) 2014 Frederic Pasteleurs <frederic@askarel.be>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program or from the site that you downloaded it
# from; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place, Suite 330, Boston, MA  02111-1307   USA
#


# redirect to main page
#if ( !isset ($CONFIGFILE))
#{
#    header ('Status: 301 Moved Permanently', false, 301);
#    header ('Location: ../index.php');
#    exit;
#}

# This will send the page start to the client
function html_header($TITLE, $EXTRAHEAD = '')
{
    printf ("<!DOCTYPE HTML>\n<html>\n <head>\n  <title>%s</title>\n%s\n </head>\n <body>\n", $TITLE, $EXTRAHEAD);
}

# This will send the page end to the client
function html_footer()
{
    echo ("\n <p>Powered by <A HREF=\"https://github.com/askarel/hsb-scripts/tree/master/concierge\">Concierge</A></p>\n </body>\n</html>\n");
}

// Dump the content of specified array
function dumparray($MYARRAY, $arrayname)
{
    printf ("<H3>Content of array '%s'</H3>\n", $arrayname);
    printf ("<ul style=\"list-style-type:none\">\n");
    foreach ($MYARRAY as $mykey => $myvalue)
	{
	    if (is_array ($MYARRAY[$mykey]))
	    {
		printf (" %s is a sub-array<br />\n", $mykey);
	    } else
	    {
		printf (" %s=%s<br />\n", $mykey , $myvalue);
	    }
	}
    printf ("</ul>\n");
}

// Return the content of the parameter, but sanitized for internal use
function sanitize_input($input)
{
    if (is_array ($input))
    { 
	foreach ($input as $key => $value)
	{
	    $input[$key] =  htmlentities ("$value", ENT_QUOTES|ENT_HTML5|ENT_SUBSTITUTE );
	}
    } else
    {
	$input = htmlentities ("$input", ENT_QUOTES|ENT_HTML5|ENT_SUBSTITUTE );
    }
    return $input;
}

// Dump all global variables and arrays
function dumpglobals()
{
    printf ("<H1>Content of \$GLOBALS array</H1>\n");
    foreach ($GLOBALS as $key => $value)
	{
	    switch ( gettype ($GLOBALS[$key]) )
		{
		case "array":
		    if ($key != "GLOBALS") // We're already dumping the $GLOBALS array
			dumparray ($GLOBALS[$key], $key); 
		    break;
		case "string":
		    printf ("Text Variable %s=%s<br />\n", $key , $value);
		    break;
		default:
		    printf ("Type of variable %s: %s<br />\n", $key , gettype ($GLOBALS[$key]) );
		    break;
		}
	}
}

// Generate a random password
function mypwgen($length = 20)
{
    $fp = fopen ("/dev/urandom", 'r');
    if (!$fp) die ("Can't access /dev/urandom to get random data. Aborting.");
    $random = fread ($fp, 512);
    fclose ($fp);
    return substr (trim (base64_encode ($random), "="), 0, $length);
}

// Abort and tell user there is something definitely wrong
function abort($str)
{
    html_header ('FAIL');
    die (sprintf ("<H1>%s</H1><br />\n", $str));
}


############### BOOTSTRAP RED TAPE (execution starts here) ###############

# First thing first: it's a modern script supposed to be used on
# decent browsers.
header ("Content-type: text/html; charset=utf8");
header ("X-Frame-Options: SAMEORIGIN");
# Start a new session or open an existing one
session_start();
// Automagically insert footer on exit
register_shutdown_function('html_footer');

// Config file location
$CONFIGFILE=dirname (__FILE__) . '/../config.php';

// Do not trust data from client: Pre-sanitize script parameters.
$SANITIZED_POST = sanitize_input ($_POST);
$SANITIZED_GET = sanitize_input ($_GET);
$SANITIZED_REQUEST = sanitize_input ($_REQUEST);

# Does the config file exist ? Bomb out if it does not.
if (!file_exists($CONFIGFILE))
    {
	abort ("Please run the setup script to create config file.");
    }

# Import config file
require_once ($CONFIGFILE);

# Open a database connection if specified in config
try
{
    if (isset ($CONFIG['mydb']))
    {
	$sqlconn = new PDO ("mysql:host=". $CONFIG['dbhostname'] . ";dbname=" . $CONFIG['mydb'] . ";charset=UTF8", $CONFIG['dbuser'], $CONFIG['dbpass']);
	$sqlconn->setAttribute (PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
	$sqlconn->setAttribute (PDO::ATTR_EMULATE_PREPARES, false);
    }
}
catch (PDOException $e) 
{
    abort (sprintf ("Database failed: %s", $e->GetMessage()));
}

# Open a LDAP connection if specified in config
//try
//{
if (isset ($CONFIG['ldapdn']))
    {
	if (!isset ($CONFIG['ldaphost']))
	{
	    $CONFIG['ldaphost'] = 'localhost';
	}
	$ldapconn = ldap_connect('ldap://' . $CONFIG['ldaphost'], $CONFIG['ldapport']);
	ldap_set_option($ldapconn, LDAP_OPT_PROTOCOL_VERSION, 3);
	$ldapbind = ldap_bind($ldapconn, $CONFIG['ldaprdn'], $CONFIG['ldappass']);
	if (!$ldapbind)
	{
	    abort (sprintf ("LDAP failed: %s" , ldap_error($ldapconn)));
	}
    }
//}
//catch ()
//{
//    abort (sprintf ("LDAP failed: %s" , ldap_error($ldapconn)));
//}
//    

# Handles we have so far:
# - $sqlconn - Open connection to MySQL database, as specified user and on specified database
# - $ldapconn - Open connection to LDAP server, bound (authenticated) to whatever is specified in config. Bound as 'anonymous' if no credentials provided.
# Variables defined and ready to use:
# - $CONFIG array, with all configuration options from file
# - $SESSION array
# Exit procedure: send the footer whenever we decide to die.
#
# Now, run the main script...
?>
