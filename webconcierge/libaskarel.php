<?php
#
# PHP toolbox - common helper functions for use in many scripts
# (c) 2018 Frederic Pasteleurs <frederic@askarel.be>
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

# Dump the content of specified array 
# $MYARRAY is the array to dump 
# $arrayname is the name of the array you dump (i know, not clean)
function dumparray($MYARRAY, $arrayname)
{
    printf ("<H3>Content of array '%s'</H3>\n", $arrayname);
    printf ("<ul style=\"list-style-type:none\">\n");
    foreach ($MYARRAY as $mykey => $myvalue) {
	if (is_array ($MYARRAY[$mykey])) {
	    printf (" %s is a sub-array<br />\n", $mykey);
	} else {
	    printf (" %s=%s<br />\n", $mykey , $myvalue);
	}
    }
    printf ("</ul>\n");
}

// DEBUG: dump all global variables and arrays. Needs rework.
function dumpglobals()
{
    printf ("<table style=\"border:3px solid red\"><tr><td>\n<H1>Content of \$GLOBALS array</H1>\n");
    foreach ($GLOBALS as $key => $value) {
	switch ( gettype ($GLOBALS[$key]) ) {
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
    printf ("</td></tr></table>\n");
}

# This will send the page start to the client. 
# $TITLE is the page title in the browser tab,
# $EXTRAHEAD is any extra tags you want between the <head> and </head> tags. This defaults to nothing.
function html_header($TITLE, $EXTRAHEAD = '')
{
    printf ("<!DOCTYPE HTML>\n<html>\n <head>\n  <meta name='viewport' content='width=device-width, initial-scale=1.0'>\n <title>%s</title>\n%s\n\n</head>\n <body>\n", $TITLE, $EXTRAHEAD);
}

# Abort script and tell user there is something definitely wrong.
# Makes a very basic HTML page in the process
# This will stop the script. It does not return to caller.
function abort($str)
{
    html_header ('FAIL');
    die (sprintf ("<H1>%s</H1><br />\n", $str));
}

# Populate chosen template
# $templatefile is the name of a text file containing the text body
# $templatedata is an array containing the variable to substitute
# Returns to caller with the template loaded and the placeholders substituted by data
# Placeholder are in the form {{ placeholder }}
function populatetemplate($templatefile, $templatedata)
{
    $template = file_get_contents($templatefile);
    foreach($templatedata as $key => $values) {
	$template = str_replace('{{ ' . $key . ' }}', $values, $template);
    }
    return $template;
}

// Generate a random string. Parameter gives the length of the random string. Defaults to 20 chars
function randomstring($length=20)
{
    $STR='';
    $CHRS='()*+,-./0123456789:;=?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}';
    for ($i=0; $i < $length; $i++) {
	$STR .= $CHRS[ mt_rand(0, strlen($CHRS)-1) ];
    }
    return $STR;
}

# This will send the page end to the client
function html_footer()
{
    echo ("\n <p>Powered by <A HREF=\"https://github.com/askarel/hsb-scripts/\">Askarel</A></p>\n </body>\n </html>\n");
}

// Taken from https://blog.michael.kuron-germany.de/2012/07/hashing-and-verifying-ldap-passwords-in-php/
function hash_password($password) // SSHA with random 4-character salt
{
    $salt = substr(str_shuffle(str_repeat('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789',4)),0,4);
    return '{SSHA}' . base64_encode(sha1( $password.$salt, TRUE ). $salt);
}

?>
