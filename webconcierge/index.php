<?php
# Load the common stuff (first thing)
include_once('./libaskarel.php');
header ("Content-type: text/html; charset=utf8");
header ("X-Frame-Options: SAMEORIGIN");

# This will send the page end to the client
function html_footer()
{
    echo ("\n <p>Powered by <A HREF=\"https://github.com/askarel/hsb-scripts/\">Askarel</A></p>\n </body>\n</html>\n");
}

// Automagically insert footer on exit
register_shutdown_function('html_footer');

html_header ('Welcome to tools.hsbxl.be');

echo "LDAP viewer for padlock codes and shared passwords <a href=\"/ldapviewer.php\">HERE</a><br />";
echo "Reset your HSBXL password <a href=\"/lostcredentials.php\">HERE</a><br />";

?>
