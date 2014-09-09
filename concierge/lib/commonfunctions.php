<?
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
if ( !isset ($CONFIGFILE))
{
    header ('Status: 301 Moved Permanently', false, 301);
    header ('Location: ../index.php');
    exit;
}


function html_header($TITLE, $EXTRAHEAD = '')
{
    printf ("<!DOCTYPE HTML>\n<html>\n <head>\n  <title>%s</title>\n%s\n </head>\n <body>\n", $TITLE, $EXTRAHEAD);
}

function html_footer()
{
    echo ("\n </body>\n</html>\n");
}

function dumparray($MYARRAY, $arrayname)
{
    printf ("<H1>Content of array '%s'</H1>\n", $arrayname);
    foreach ($MYARRAY as $key => $value)
	{
	    if (is_array ($MYARRAY[$key]))
	    {
		echo "$key is an array<br />";
	    } else
	    {
		printf ("%s=%s<br />\n", $key , $value);
	    }
	}
}

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

?>