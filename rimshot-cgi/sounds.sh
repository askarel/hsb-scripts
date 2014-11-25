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

readonly DIR_AUDIOFILES="/srv/sharedfolder/trolling_page"
readonly PAGETITLE="Rimshot and other shit"
readonly ME=$(basename $0)
readonly CSSDIR="$DIR_AUDIOFILES/.CSS"
readonly TEMPLATE="$CSSDIR/$ME-template.html"
# buttons definition
HTMLTROLLBUTTON='<BUTTON TYPE="BUTTON" VALUE="Submit" CLASS="%s soundBtn" ONCLICK="troll('\''%s'\'')">%s</BUTTON>\n'
# HTMLSIDEBAR='<A HREF="#%s">%s</A> <br />\n'
#internals
readonly CSSMETHOD="CSS"
readonly JSONMETHOD="JSON"
readonly JSMETHOD="JS"
readonly POSTSPEAKMETHOD="SPEAK"
readonly POSTRANDOMMETHOD="RANDOM"
readonly PLAYPROG="paplay"
readonly SPEECHMETHOD="espeakmethod"
# readonly FOOTER="Proudly brought to you by Askarel and many contributors in HSBXL."
#DEBUG=blaah

# Speech method: using espeak
# Parameter 1: text to say
# parameter 2: language
espeakmethod()
{
    SPEECHBIN="$(which espeak)"
    if [ $? = 0 ]; then # Installed ? Something to say ?
	SPEECHBAR="Speech synth: <INPUT TYPE=\"text\"  NAME=\"SPEAK\" ID=\"SPEAK\" onkeydown=\"if (event.keyCode == 13 ) {troll ('SPEAK=' + document.getElementById('SPEAK').value); return false; }\" />"
	test -n "$1" && $SPEECHBIN "$1" 
    fi
}

# Speech method: using flite
# Parameter 1: text to say
flitemethod()
{
    SPEECHBIN="$(which flite)"
    if [ $? = 0 ]; then # Installed ? Something to say ?
	SPEECHBAR="Speech synth: <INPUT TYPE=\"text\"  NAME=\"SPEAK\" ID=\"SPEAK\" onkeydown=\"if (event.keyCode == 13 ) {troll ('SPEAK=' + document.getElementById('SPEAK').value); return false; }\" />"
	test -n "$1" && $SPEECHBIN -t "$1" 
    fi
}

# Dump error message specified by parameter 1
htmlbombmsg()
{
cat << BOMB
<!DOCTYPE html>
<HTML>
 <HEAD>
  <TITLE>$PAGETITLE</TITLE>
 </HEAD>
 <BODY>
    <H1>$1</H1><BR />Troll another day...
 </BODY>
</HTML>
BOMB
}

# Error 404: file specified as parameter 1 not found
err404()
{
printf 'Status: 404 not found\nContent-Type: text/html\n\n'
htmlbombmsg "404 FILE \"$(basename "$1")\" NOT FOUND"
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
# parameter 1: target directory
# parameter 2: requested file hash
# parameter 3: Program to run. If empty, just print it out
# THIS FUNCTION IS EXPOSED TO USER INPUT
pickfilehash()
{
    find "$1" -xtype f \( -iname "*" ! -iname ".*" \) -not -path "*/.*"  -exec /bin/sh -c \
	'printf "%s %s\n" "$(echo -n "{}" | md5sum | cut -d " " -f 1 )" "{}"' \; | while read trollhash trollfile; do 
	    test "$trollhash" = "$2" && ${3:-echo} "$trollfile"
	 done
}

# Spit out the HTML code for a button
# Parameter 1: full path to file
printhtmlbuttonhash()
{
    local btnhash="$(echo -n "$1" | md5sum | cut -d ' ' -f 1 )"
    printf "    $HTMLTROLLBUTTON" "$btnhash" "$btnhash" "$(basename "$1")"
}

# Make a section with anchor for a category
# Parameter 1: path to generate buttons for
# Parameter 2: maximum depth
printhtmlsectionhash()
{
    local ITEMNAME="${1#$DIR_AUDIOFILES}"
    test -n "$ITEMNAME" && printf '<DIV ID="%s"><H2>%s</H2></DIV>\n' "$(echo -n "$1" | md5sum | cut -d " " -f 1 )" "$ITEMNAME"
    find "$1" -maxdepth 1 -xtype f \( -iname "*" ! -iname ".*" \) -not -path "*/.*" |while read btn; do printhtmlbuttonhash "$btn"; done
}

# Show the page.
showpagehash()
{
if [ -f "$TEMPLATE" ]; then
    if [ -d "$DIR_AUDIOFILES" ]; then
	# Sidebar 
	SIDEBAR="$(find "$DIR_AUDIOFILES" -xtype d \( -iname "*" ! -iname ".*" ! -wholename "$DIR_AUDIOFILES" \) -not -path "*/.*"  -exec /bin/sh -c \
	    'printf "<A HREF=\"#%s\">%s</A> <br />\n" "$(echo -n "{}" | md5sum | cut -d " " -f 1 )" "$(basename "{}")"' \;)"
	# Make categories. Skip anything hidden
	TROLLBODY="$(find "$DIR_AUDIOFILES" -xtype d \( -iname "*" ! -iname ".*" \) -not -path "*/.*" | while read line; do printhtmlsectionhash "$line"; done)"
    fi
    # Prime the template variables and show the page
    export PAGETITLE ME TROLLBODY SIDEBAR SPEECHBAR FOOTER
    cat $TEMPLATE | envsubst
else # Template not found. Complain loudly.
    htmlbombmsg "MISSING TEMPLATE: $TEMPLATE"
fi
}

# Valid speech method ?
test -n "$SPEECHMETHOD" && $SPEECHMETHOD

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
    "$JSMETHOD")
	JSFILE="$( echo "$QUERY_STRING"|cut -d '=' -f 2 )"
	if [ -n "$( pickfile "$CSSDIR" "$JSFILE" )" ]; then
	    printf "Content-type: text/javascript\n\n"
	    cat "$( pickfile "$CSSDIR" "$JSFILE" )"
	else
	    err404 "$JSFILE"
	fi
	;;
    "$JSONMETHOD")
	printf "Content-type: text/javascript\n\n"
	## TODO: Rewrite the trollbody generator
	;;
    *) # Catch-all method. Data is in the POST
	# Process POSTed data
	printf 'Content-type: text/html\n\n'
	if [ "$REQUEST_METHOD" = "POST" -a -n "$CONTENT_LENGTH" ]; then
	    read -n "$CONTENT_LENGTH" POSTDATA
	    test -n "$DEBUG" && logger -t $ME-post "POST data: '$POSTDATA'"
	    if [ -n "$POSTDATA" -a "$POSTDATA" != "[object HTMLFormElement]" ]; then # Is there something in the POSTed data ?
		POSTDATAVAR="$(echo -n "$POSTDATA"|cut -d '=' -f 1)"
		case "$POSTDATAVAR" in
		    "$POSTRANDOMMETHOD")# Random button (roll the dice)
			$PLAYPROG "$(find "$DIR_AUDIOFILES" -xtype f \( -iname "*" ! -iname ".*" \) -not -path "*/.*"|shuf -n 1)" &
		        ;;
		    "$POSTSPEAKMETHOD") # Speech synth method.
			SPEECHTEXT="$(echo "$POSTDATA" | cut -d '=' -f 2-)"
			# SPEECHLANG=
			test -n "$SPEECHMETHOD" && $SPEECHMETHOD "$SPEECHTEXT" "$SPEECHLANG" &
			;;
		    *)# The rest...
			pickfilehash "$DIR_AUDIOFILES" "$POSTDATAVAR" "$PLAYPROG"
			;;
		esac
	    fi
	else
	    showpagehash
	fi
	;;
esac
