<?php
#
# A simple LDAP viewer
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

# Load the common stuff (first thing)
include_once('./libaskarel.php');


static $CONFIG = array (
# LDAP parameters
	'ldaphost' => 'localhost',
	'ldapport' => 389,
	'ldapdn' => 'dc=example,dc=org',
	'ldapuserou' => 'users',
	'orgname' => 'My Organization',
	'Contact informations' => array (
		'subtree' => 'ou=users',
		'User name' => 'uid',
		'Full name' => 'cn',
		'E-mail address' => 'mail',
		'Phone number' => 'homephone'
		)
);

# This will send the page end to the client
function html_footer()
{
    echo ("\n <p>Powered by <A HREF=\"https://github.com/askarel/hsb-scripts/\">Askarel</A></p>\n </body>\n</html>\n");
}

function LoginPage($ButtonMessage)
{
	html_header ('Hello');
	global $MissingUsrText, $MissingPwText, $CONFIG;
	if ( ($_SERVER['REQUEST_METHOD'] == "POST") and ($_REQUEST['user'] == "") ) $MissingUsrText="Field cannot be empty" ;
	if ( ($_SERVER['REQUEST_METHOD'] == "POST") and ($_REQUEST['pass'] == "") ) $MissingPwText="Field cannot be empty" ;
	printf ("<div>\n");
	printf (" <H1>%s Simple LDAP viewer</H1>\n",$CONFIG['orgname']);
	printf (" <FORM Method=\"POST\" Action=\"%s\">\n", $_SERVER['SCRIPT_NAME']);
	printf ("  Username: <INPUT type=\"text\" size=20 name=\"user\">%s<br />\n", $MissingUsrText);
	printf ("  Password: <INPUT type=\"password\" size=20 name=\"pass\">%s<br />\n", $MissingPwText);
	printf ("  Data requested: <select name=\"dataObject\">\n");
	foreach ($CONFIG as $configkey => $configvalue) // Populate the drop-down menu
	    if (is_array ($CONFIG[$configkey]) and isset ($CONFIG[$configkey]['subtree'])) printf (" <option value=\"%s\">%s</option>\n", $configkey, $configkey);
	printf ("  </select><br />\n");
	printf (" <INPUT type=\"submit\" value=\"Login\"><H3>%s</H3>\n", $ButtonMessage);
	printf (" </FORM>\n");
	printf ("</div>\n");
}

# First thing first: it's a modern script (?) supposed to be used on
# decent browsers.
header ("Content-type: text/html; charset=utf8");
header ("X-Frame-Options: SAMEORIGIN");
// Automagically insert footer on exit
register_shutdown_function('html_footer');

switch ($_SERVER['REQUEST_METHOD']) {
    case 'GET':
	LoginPage("");
	break;
    case 'POST':
	if ( ($_REQUEST['pass'] == "") or ($_REQUEST['user'] == "") ) // username/password fields filled ?
	    LoginPage("");
	else
	{
	    $ldapconn = ldap_connect ($CONFIG['ldaphost'], $CONFIG['ldapport']);
	    ldap_set_option($ldapconn, LDAP_OPT_PROTOCOL_VERSION, 3);
	    $BindDN = "uid=" . $_REQUEST['user'] . ",ou=" . $CONFIG['ldapuserou'] . "," . $CONFIG['ldapdn'];
	    $ldapbind = ldap_bind($ldapconn, $BindDN, $_REQUEST['pass']);
	    if (!$ldapbind)
		LoginPage (sprintf ("LDAP failed: %s" , ldap_error($ldapconn)));
	    else
	    { // Bind successful
		foreach ($CONFIG as $configkey => $configvalue)
		{
		    if (is_array ($CONFIG[$configkey]) and ($configkey == $_REQUEST['dataObject']) and isset ($CONFIG[$configkey]['subtree']))
			{ // Only display something if request matches config
			    $dataSubTree=$CONFIG[$configkey]['subtree'] . ',' . $CONFIG['ldapdn'];
			    html_header ("Data for subtree " . $dataSubTree);
			    printf ("  Logged is as %s (DN: %s)<br />\n", $_REQUEST['user'], $BindDN);
			    printf ("  <table style=\"border: 1px solid black\">\n");
			    printf ("   <caption><H3>Data for subtree %s</H3></caption>\n   <tr style=\"border: 1px solid black\">\n", $dataSubTree);
			    foreach ($CONFIG[$configkey] as $columnkey => $columnvalue) // Table header
				if ($columnkey != "subtree") 
				{
				    printf ("    <th style=\"border: 1px solid black\">%s</th>\n", $columnkey); // Print table header
				    $ldapattributes[] = $CONFIG[$configkey][$columnkey]; // Build LDAP attributes list to search
				}
			    printf ("   </tr>\n");
			    $ldap_results = ldap_search ($ldapconn, $dataSubTree, "(" . $ldapattributes[0] ."=*)", $ldapattributes);
			    $ldap_entries = ldap_get_entries ($ldapconn, $ldap_results);
			    for ($i=0; $i<$ldap_entries['count']; $i++)
				{
				    printf ("   <tr style=\"border: 1px solid black\">\n");
				    foreach ($ldapattributes as $columnkey => $columnvalue)
					printf ("    <td style=\"border: 1px solid black\">%s</td>\n", $ldap_entries[$i][strtolower ($columnvalue)][0]);
				    printf ("   </tr>\n");
				}
			    printf ("  </table> \n");
			    printf ("  <br />\n  You are already logged out. Reload page to clear screen and/or request other data.<br />\n");
			}
		}
	    }
	    ldap_unbind ($ldapconn);
	}
	break;
    default: 
	abort ("Invalid method: "  . $_SERVER['REQUEST_METHOD']);
}

?>