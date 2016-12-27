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


function html_header($TITLE, $EXTRAHEAD = '')
{
    printf ("<!DOCTYPE HTML>\n<html>\n <head>\n  <title>%s</title>\n%s\n </head>\n <body>\n", $TITLE, $EXTRAHEAD);
}

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
function mypwgen($length = 15)
{
    $fp = fopen ("/dev/urandom", 'r');
    if (!$fp) die ("Can't access /dev/urandom to get random data. Aborting.");
    $random = fread ($fp, 512);
    fclose ($fp);
    return substr (trim (base64_encode ($random), "="), 0, $length);
}

############### BOOTSTRAP RED TAPE (execution starts here) ###############

# First thing first: it's a modern script supposed to be used on
# decent browsers.
header ('Content-type: text/html; charset=utf8');
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
	html_header ('FAIL');
	echo ("Please run the setup script to create config file.\n");
	die();
    }
# Import config file
require_once ($CONFIGFILE);

?>
