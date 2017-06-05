<?php
#
# Concierge for Hackerspace Brussels - Web front-end
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

# Load the common stuff (first thing)
include_once('./lib/commonfunctions.php');

$MissingUsrText=""; 
$MissingEmailText="";

function lostpw_page()
{
	html_header ("Password reset");
	global $MissingUsrText, $MissingEmailText, $CONFIG, $SANITIZED_REQUEST;
	if ( ($_SERVER['REQUEST_METHOD'] == "POST") and ($_REQUEST['user'] == "") ) $MissingUsrText="Field cannot be empty" ;
	if ( ($_SERVER['REQUEST_METHOD'] == "POST") and ($_REQUEST['email'] == "") ) $MissingEmailText="Field cannot be empty" ;
	printf ("<div>\n");
	printf (" <H1>Password reset form for %s</H1>\n",$CONFIG['CAorgname']);
	printf (" In order to reset your password, we will need a couple of informations about you first:<br />\n");
	printf (" <FORM Method=\"POST\" Action=\"%s\">\n", $_SERVER['SCRIPT_NAME']);
	printf ("  Username: <INPUT type=\"text\" size=20 name=\"user\" value=\"%s\">%s<br />\n", $SANITIZED_REQUEST['user'], $MissingUsrText);
	printf ("  E-mail address: <INPUT type=\"text\" size=20 name=\"email\" value=\"%s\">%s<br />\n", $_REQUEST['email'], $MissingEmailText);
	printf (" <INPUT type=\"submit\" value=\"Reset password\">\n");
	printf (" </FORM>\n");
	printf ("<a HREF=\"index.php\">Go back to login page</a><br />\n");
	printf ("<a HREF=\"newaccount.php\">Create new account</a><br />\n");
	printf ("</div>\n");
}

function print_mailsent($sentto)
{
	printf ("<div>\n");
	printf (" <H1>Password request sent.</H1>\n");
	printf (" Your password reset request has been sent. Please check your mailbox (%s) and follow the instructions<br />\n<br />\n", $sentto);
	printf ("<a HREF=\"index.php\">Go back to login page</a><br />\n");
	printf ("<a HREF=\"newaccount.php\">Create new account</a><br />\n");
	printf ("</div>\n");
}

// Validate supplied data...
if ( ($_SERVER['REQUEST_METHOD'] == "POST") and ($_REQUEST['user'] != "") and ($_REQUEST['email'] != "") )
    {
//	$rdn="uid=" . $SANITIZED_REQUEST['user'] . ",ou=" . $CONFIG['ldapuserou'] . "," . $CONFIG['ldapdn'];
	$dn="ou=" . $CONFIG['ldapuserou'] . "," . $CONFIG['ldapdn'];
	// What we want to get from LDAP
	$userrq = array ("cn", "uid", "mail");
	$filter="(|(uid=" . $SANITIZED_REQUEST['user'] . "))";
	$result = ldap_search ($ldapconn, $dn, $filter, $userrq);
	$infos = ldap_get_entries ($ldapconn, $result);
	// Checking supplied data. They have to match what we know about the user requesting the password reset.
	// This check is needed to limit the amount of bogus reset attempts
	if ( ($infos['count'] == 1) and ($infos[0]['uid'][0] == $_REQUEST['user']) and ($infos[0]['mail'][0] == $_REQUEST['email']) )
	{
	    echo ($infos[0]['cn'][0] . "   " . $infos[0]['uid'][0] . "  " . $infos[0]['mail'][0]);
	}
    }

if ($_SERVER['REQUEST_METHOD'] == "POST")
{
    print_mailsent($SANITIZED_REQUEST['email']);
}
else
{
    lostpw_page();
}

#dumparray ($infos[0]);
#dumpglobals();

?>
