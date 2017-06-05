<?php
#
# Concierge for Hackerspace Brussels - Web front-end - New account creation script
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

function printhtml()
{
printf ("  <p>So you want to become a member of %s, this is great.<br /></p>\n", $CONFIG['CAorgname']);
printf ("  <p>In order to make it happen, you need to fill the informations below:<br /></p>\n");
printf (" <FORM Method=\"POST\" Action=\"%s\">\n", $_SERVER['SCRIPT_NAME']);
//printf ("  Client certificate key size: <keygen name=\"pubkey\" challenge=\"randomchars\"><br />\n");
printf ("  First name:		<INPUT type=\"text\" size=20 name=\"firstname\" value=\"%s\"><font color=\"red\">%s</font><br />\n", $FIELDS['firstname'], $FIELDS_HELP['firstname']);
printf ("  name:			<INPUT type=\"text\" size=20 name=\"name\" value=\"%s\"><font color=\"red\">%s</font><br />\n", $FIELDS['name'], $FIELDS_HELP['name']);
printf ("  Username/screen name:	<INPUT type=\"text\" size=20 name=\"nickname\" value=\"%s\"><font color=\"red\">%s</font>This is what to put in the login box. If empty, the combination firstname_name will be used. You obviously don't want that.<br />\n", $FIELDS['nickname'], $FIELDS_HELP['nickname']);
printf ("  Password:		<INPUT TYPE=\"password\" size=20 name=\"password\" value=\"%s\">If this field is left empty, i will generate one for you.<br />\n", $FIELDS['password']);
printf ("  Password (again)		<INPUT TYPE=\"password\" size=20 name=\"password2\" value=\"\"><font color=\"red\">%s</font><br />\n", $FIELDS_HELP['password2']);
printf ("  Language:		<INPUT type=\"text\" size=20 name=\"lang\" value=\"%s\">If empty or non-existent, use system default.<br />\n", $FIELDS['lang']);
printf ("  e-mail address:		<INPUT type=text size=20 name=emailaddress value=\"%s\"><font color=\"red\">%s</font><br />\n", $FIELDS['emailaddress'], $FIELDS_HELP['emailaddress']);
printf ("  PGP/GnuPG public key ID:	<INPUT type=text size=20 name=openpgpkeyid value=\"%s\"><br />\n", $FIELDS['openpgpkeyid']);
printf ("  Phone number:		<INPUT type=text size=20 name=phonenumber value=\"%s\"><br />\n", $FIELDS['phonenumber']);
printf ("  Birthdate:		<INPUT type=text size=20 name=birthdate value=\"%s\"><font color=\"red\">%s</font><br />\n", $FIELDS['birthdate'], $FIELDS_HELP['birthdate']);
printf ("  Explain why you want to be a member: <br /> <TEXTAREA cols=\"80\" rows=\"25\" name=informations>%s</TEXTAREA><font color=\"red\">%s</font><br />\n", $FIELDS['informations'], $FIELDS_HELP['informations']);
// printf ("  SSH public key(s): <br /> <TEXTAREA cols=\"80\" rows=\"10\" name=sshpubkeys>%s</TEXTAREA><br />\n", $FIELDS['sshpubkeys']);
printf (" <INPUT type=\"submit\" value=\"Submit\">\n");
printf (" </FORM>\n");
}

dumpglobals();

?>
