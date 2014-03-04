#!/bin/bash

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
PAGETITLE="Rimshot and other shit"
#DIR_AUDIOFILES="./filez"
ME=$(basename $0)
CSSDIR="$DIR_AUDIOFILES/.CSS"
CSSMETHOD="CSS"
JSONMETHOD="JSON"
PLAYPROG="paplay"

# Create the hash databases. Ignores any file/directory beginning with a dot.
FILEHASHDB="$(find "$DIR_AUDIOFILES" -xtype f \( -iname "*" ! -iname ".*" \) -exec /bin/sh -c 'printf "%s %s\n" "`echo -n \"{}\"|md5sum| cut -d  \" \" -f 1`" "{}" ' \;)"
DIRHASHDB="$(find "$DIR_AUDIOFILES" -xtype d \( -iname "*" ! -iname ".*" \) -exec /bin/sh -c 'printf "%s %s\n" "`echo -n \"{}\"|md5sum| cut -d  \" \" -f 1`" "{}" ' \;)"

# Self explanatory.
err404()
{
cat << ERR404
Status: 404 not found
Content-Type: text/html

<!DOCTYPE html>
<HTML>
 <HEAD>
  <TITLE>$PAGETITLE</TITLE>
 </HEAD>
 <BODY>
    <H1>404 FILE "$(basename "$1")" NOT FOUND</H1><BR />Troll another day.
 </BODY>
</HTML>
ERR404
}

# Pick a file from specified directory
# Secure handling of user-defined input: avoid the abuse of the '../' trick.
# Return a full path to a file if a match is found in directory.
# Return nothing if file not found/directory empty
# parameter 1: target directory
# parameter 2: requested file
pickfile()
{
    ls -1 "$1" | while read line; do
    test "$line" = "$2" && echo "$1/$line"
    done
}

# Pick a file using the filename hash
# Return full path to the file if in database.
# Return nothing if there is no match
# parameter 1: requested file hash
# THIS FUNCTION IS EXPOSED TO USER INPUT
pickfilehash()
{
    echo "$FILEHASHDB"|grep "$1" | cut -d ' ' -f 2-
}

# Show the page
showpagehash()
{
cat << EOM
 <HEAD>
  <TITLE>$PAGETITLE</TITLE>
  <link rel="stylesheet" href="$ME?CSS=trollin.css" type="text/css" />
 </HEAD>
 <BODY>
  <SCRIPT>
    function reqListener() {
	console.log(this.responseText);
    }


    function troll(sound) {
	var trollrequest = new XMLHttpRequest();
	trollrequest.onload = reqListener;
	trollrequest.open ("POST", "$ME", true);
	trollrequest.send (sound);
    }
  </SCRIPT>
  <DIV ID="TOP"><H1>HSBXL TROLLING PAGE 2.0 !!!</H1></DIV>
EOM

if [ -d "$DIR_AUDIOFILES" ]; then
cat <<EOM
  <FORM ACTION="$ME" method="POST">
   <BUTTON TYPE="BUTTON" VALUE="SUBMIT" NAME="RANDOM" CLASS="RANDOM soundBtn" ONCLICK="troll('RANDOM');">RANDOM SOUND</BUTTON>
   Jump to a section:
EOM

    echo "$DIRHASHDB"| while read directoryhash directoryname; do # Make jump bar
	test "$directoryname" != "$DIR_AUDIOFILES" && printf "    <A HREF=\"#%s\">%s</A>\n" "$directoryhash" "$(basename "$directoryname")"
    done
    echo "$DIRHASHDB"| while read directoryhash directoryname; do # Make categories
	test "$directoryname" != $DIR_AUDIOFILES && printf "   <DIV ID=\"%s\"><H2>%s <A HREF=\"#TOP\">&uarr;</A></H2></DIV>\n" "$directoryhash" "$(basename "$directoryname")"
	echo "$FILEHASHDB" | while read filehash filename; do # Make buttons
	    test "$(dirname "$filename")" = "$directoryname" && 
		printf "    <BUTTON TYPE=\"BUTTON\" VALUE=\"Submit\" ID=\"%s\" NAME=\"%s\" CLASS=\"%s soundBtn\" ONCLICK=\"troll('%s')\">%s</BUTTON>\n" "$filehash" "$filehash" "$filehash" "$filehash" "$(basename "$filename")"
	done
    done
fi
printf "  </FORM>\n </BODY>\n"
}

case "$( echo "$QUERY_STRING"|cut -d '=' -f 1 )" in
    "$CSSMETHOD")
	CSSFILE="$( echo "$QUERY_STRING"|cut -d '=' -f 2 )"
	if [ -n "$( pickfile "$CSSDIR" "$CSSFILE" )" ]; then
	    printf "Content-type: text/css\n\n"
	    cat "$( pickfile "$CSSDIR" "$CSSFILE" )"
	    else
	    err404 "$CSSFILE"
	fi
	;;
    "$JSONMETHOD") # Dump a JSON version of the page
	printf 'Content-type: application/json\n\n'
	printf '{\n	"Title:": "%s"' "$PAGETITLE"
	if [ -d "$DIR_AUDIOFILES" ]; then
	    printf ',\n		"buttons": {\n		"RANDOM": "RANDOM"'
	    echo "$DIRHASHDB"| while read directoryhash directoryname; do 
		test "$directoryname" != "$DIR_AUDIOFILES" && jdirectoryname="$(basename "$directoryname")"
		printf ',\n		"%s": {\n			"directoryname": "%s"' "$directoryhash" "$jdirectoryname"
		echo "$FILEHASHDB" | while read filehash filename; do # Make buttons
		    test "$(dirname "$filename")" = "$directoryname" && 
			printf ',\n			"%s": "%s"' "$filehash" "$(basename "$filename")" 
		done
		printf '\n			}'
	    done
	    printf '\n		}'
	fi
	printf "\n}\n"
	;;
    *) # Catch-all method. Data is in the POST
	printf "Content-type: text/html\n\n<!DOCTYPE html>\n<HTML>\n"
	# Process POSTed data
	if [ "$REQUEST_METHOD" = "POST" -a -n "$CONTENT_LENGTH" ]; then
	    read -n "$CONTENT_LENGTH" POSTDATA
	    logger -t $ME-post "POST data: '$POSTDATA'"
	    if [ -n "$POSTDATA" -a "$POSTDATA" != "[object HTMLFormElement]" ]; then # Is there something in the POSTed data ?
		POSTDATAVAR="$(echo -n "$POSTDATA"|cut -d '=' -f 1)"
		case "$POSTDATAVAR" in
		    "RANDOM")
			$PLAYPROG "$(pickfilehash "$(echo "$FILEHASHDB" |cut -d ' ' -f 1|shuf -n 1)")" & #" choke alert
		        ;;
		    *)
		        test -n "$( pickfilehash "$POSTDATAVAR" )" && $PLAYPROG "$( pickfilehash "$POSTDATAVAR")"
			;;
		esac
	    fi
	fi
	showpagehash
	printf "</HTML>\n"
	;;
esac
