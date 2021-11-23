<?php
# Load the common stuff (first thing)
include_once('./libaskarel.php');
header ("Content-type: text/html; charset=utf8");
header ("X-Frame-Options: SAMEORIGIN");


// Automagically insert footer on exit
register_shutdown_function('html_footer');

html_header ('Welcome to tools.hsbxl.be');

echo "LDAP viewer for padlock codes and shared passwords <a href=\"/ldapviewer.php\">HERE</a><br />";
echo "Reset your HSBXL password <a href=\"/lostcredentials.php\">HERE</a><br />";

?>
