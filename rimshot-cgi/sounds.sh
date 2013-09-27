#!/bin/sh

# The rimshot CGI script - Trolling HSBXL with style
# (c) 2012 Frederic Pasteleurs <askarel@gmail.com>
#
# CSS and minor improvements by ZipionLive
# Space-in-filename bug fix by Tom Behets
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

DIR_AUDIOFILES="/srv/sharedfolder/trolling_page"
DIR_AUDIOFILES="./filez"
ME=$(basename $0)
CSSDIR="$DIR_AUDIOFILES/.CSS"
PLAYMETHOD="PLAY"
CSSMETHOD="CSS"
RANDOMMETHOD="RANDOM"
PLAYPROG="paplay"

# Pick a file from specified directory
# Secure handling of user-defined input: avoid the abuse of the '../' trick.
# Return a full path to a file if a match is found in directory.
# Return nothing if file not found/directory empty
# parameter 1: target directory
# parameter 2: requested file
pickfile()
{
    ls -1 "$1" | while read line; do
	test "$line" = "$(echo "$2"| sed -e 's/+/ /')" && echo "$1/$line"
    done
}

# Show the html page
showpage()
{
cat << EOM
Content-type: text/html

<!DOCTYPE html>
<HTML>
 <HEAD>
  <TITLE>Rimshot and other shit</TITLE>
  <link rel="stylesheet" href="$ME?CSS=trollin.css" type="text/css" />
 </HEAD>
 <BODY>
  <H1>HSBXL TROLLING PAGE</H1>
EOM

if [ -d "$DIR_AUDIOFILES" ]; then
    echo "  <FORM ACTION=\"$ME\" method=\"GET\">"
    echo "   <INPUT TYPE=\"SUBMIT\" VALUE=\"RANDOM\" NAME=\"$RANDOMMETHOD\" CLASS=\"RANDOM soundBtn\"></INPUT>"
    ls -1 "$DIR_AUDIOFILES" | while read line ; do
	echo "   <INPUT TYPE=\"SUBMIT\" VALUE=\"$line\" NAME=\"$PLAYMETHOD\" CLASS=\"$(echo "$line"| sed -e 's/ /+/') soundBtn\"></INPUT>"
    done
    echo "  </FORM>"
fi

printf " </BODY>\n</HTML>\n"
}

# content dispatcher
case "$( echo "$QUERY_STRING"|cut -d '=' -f 1 )" in
    "$PLAYMETHOD")
	showpage
	SNDFILE="$( echo "$QUERY_STRING"|cut -d '=' -f 2 )"
	test -n "$( pickfile "$DIR_AUDIOFILES" "$SNDFILE" )" && $PLAYPROG "$( pickfile "$DIR_AUDIOFILES" "$SNDFILE" )"
	;;
    "$CSSMETHOD")
	CSSFILE="$( echo "$QUERY_STRING"|cut -d '=' -f 2 )"
	test -n "$( pickfile "$CSSDIR" "$CSSFILE" )" && printf "Content-type: text/css\n\n" && cat "$( pickfile "$CSSDIR" "$CSSFILE" )"
	;;
    "$RANDOMMETHOD")
	showpage
	$PLAYPROG "$DIR_AUDIOFILES/$(ls -1 "$DIR_AUDIOFILES" |shuf -n 1)" &
	;;
    *)
	showpage
	;;
esac
