<?
#
# Concierge for Hackerspace Brussels - Web front-end - new member entry module
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
if (!isset($CONFIGFILE))
{
    header('Status: 301 Moved Permanently', false, 301);
    header('Location: ../index.php');
    exit;
}

html_header ('New member');
printf ("  <p>So you want to become a member of %s, this is great.<br /></p>\n", $CONFIG['orgname']);
printf ("  <p>In order to make it happen, you need to fill the informations below:<br /></p>\n");
printf (" <FORM Method=\"POST\" Action=\"%s\">\n", $_SERVER['SCRIPT_NAME']);
printf ("  First name: <INPUT type=\"text\" size=20 name=\"firstname\" value=\"%s\">%s<br />\n", $SANITIZED_POST['firstname'], $MissingFirstNameText);
printf ("  name: <INPUT type=\"text\" size=20 name=\"name\" value=\"%s\">%s<br />\n", $SANITIZED_POST['name'], $MissingNameText);
printf ("  Username/screen name: <INPUT type=\"text\" size=20 name=\"nickname\" value=\"%s\">This is what to put in the login box. If empty, the combination firstname_name will be used. You obviously don't want that.<br />\n", $SANITIZED_POST['nickname']);
printf ("  Phone number: <INPUT type=text size=20 name=phonenumber value=\"%s\"><br />\n", $SANITIZED_POST['phonenumber']);
printf ("  Explain why you want to be a member: <br /> <TEXTAREA cols=\"80\" rows=\"25\" name=why_member>%s</TEXTAREA><br />\n", $SANITIZED_POST['why_member']);
printf ("  Birthdate: <INPUT type=text size=20 name=birthdate value=\"%s\"><br />\n", $SANITIZED_POST['birthdate']);
printf ("  PGP/GnuPG public key ID: <INPUT type=text size=20 name=openpgpkeyid value=\"%s\">If the key is valid, all mail notifications will be encrypted<br />\n", $SANITIZED_POST['openpgpkeyid']);
printf ("  SSH public key(s): <br /> <TEXTAREA cols=\"80\" rows=\"10\" name=sshpubkeys>%s</TEXTAREA><br />\n", $SANITIZED_POST['sshpubkeys']);
printf ("  e-mail address: <INPUT type=text size=20 name=emailaddress value=\"%s\"><br />\n", $SANITIZED_POST['emailaddress']);
printf ("  Password: <INPUT type=\"password\" size=20 name=\"hsbpass\">%s<br />\n", $MissingPwText);
printf ("  Confirm password: <INPUT type=\"password\" size=20 name=\"hsbpass2\">%s<br />\n", $NoMatchingPass);
printf (" <INPUT type=\"submit\" value=\"Submit\">\n");
printf (" </FORM>\n");


?>