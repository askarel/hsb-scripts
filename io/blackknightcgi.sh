#!/bin/bash
#
#	Crude web interface, for use with a decent web server (Apache/nginx)
#
#	(c) 2014 Frederic Pasteleurs <frederic@askarel.be>
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# To get the data used by this script, you need to make a partial dump of Mediawiki database with this command: 
# mysql -uUSER -pPASSWORD DATABASE -s --skip-column-names -e "select concat ('# ',user_name, user_password, ':', user_email) from smw_user where user_password not like '';" > ~/SMWUserData.txt
# You will then need to uncoment the users that need access.

# Some static
readonly ME=$(basename $0)
readonly SMWUSERDB="/var/local/SMWUserData.txt"

# Finding the controller
test -x './blackknightio' && BLACKKNIGHTIO='./blackknightio'
test -x '/usr/local/bin/blackknightio' && BLACKKNIGHTIO='/usr/local/bin/blackknightio'
# debug
#BLACKKNIGHTIO="/usr/bin/logger"

function urldecode()
{
    printf '%b' "${1//%/\\x}"
}

printf 'Content-type: text/html\n'

# Process POSTed data
if [ "$REQUEST_METHOD" = "POST" -a -n "$CONTENT_LENGTH" ]; then
    read -n "$CONTENT_LENGTH" POSTDATA
    DOORUSER="$(echo "$POSTDATA"| sed -n 's/^.*user=\([^&]*\).*$/\1/p')"
    DOORPASS="$(echo "$POSTDATA"| sed -n 's/^.*pass=\([^&]*\).*$/\1/p')"
    test -z "$DOORUSER" && MISSINGUSERTEXT='<font color="red">Username is required</font>'
    test -z "$DOORPASS" && MISSINGPASSTEXT='<font color="red">Password is required</font>'
fi
# If we have username/password, set a cookie for the next 24 hours
#test -n "$DOORUSER" -a -n "$DOORPASS" && printf 'Set-Cookie: dooruser=%s; doorpass=%s; path=%s; expires=%s\r\n' "$DOORUSER" "$DOORPASS" "$SCRIPT_NAME" "$(date --date='now + 1 day')"

# Empty line
echo ""
# Datafile present and usable ?
test -f "$SMWUSERDB" || MISSINGUSERTEXT='<font color="red">Missing database file: no login possible</font>'

# Check supplied password
if [ -n "$DOORUSER" -a -n "$DOORPASS" -a -f "$SMWUSERDB" ]; then
    DOORUSER="$(urldecode "$DOORUSER")"
    DOORPASS="$(urldecode "$DOORPASS")"
    SMWSALT="$(cat "$SMWUSERDB" |sed '/^#/ d'|awk "BEGIN { FS=\":\"; IGNORECASE=1 }; \$1 == \"$DOORUSER\" { print \$3 };")"
    SMWHASH="$(cat "$SMWUSERDB" |sed '/^#/ d'|awk "BEGIN { FS=\":\"; IGNORECASE=1 }; \$1 == \"$DOORUSER\" { print \$4 };")"
    test -z "$SMWHASH" -o -z "$SMWSALT" && MISSINGPASSTEXT='<font color="red">Login incorrect.</font>'
    DOORHASH="$(echo -n "${SMWSALT}-$(echo -n "$DOORPASS"|md5sum|cut -d ' ' -f 1)"|md5sum|cut -d ' ' -f 1)" #"
    test -n "$SMWHASH" -a "$SMWHASH" != "$DOORHASH" && MISSINGPASSTEXT='<font color="red">Login incorrect.</font>'
    test "$SMWHASH" = "$DOORHASH" -a -x "$BLACKKNIGHTIO" && $BLACKKNIGHTIO "open" "webif $DOORUSER" > /dev/null
fi

# Beep!
test "$CONTENT_LENGTH" -eq 0 && unset CONTENT_LENGTH
test -z "$CONTENT_LENGTH" -a "$QUERY_STRING" = "beep" && test -x "$BLACKKNIGHTIO" && $BLACKKNIGHTIO beep > /dev/null

# Dumping web page
printf '<!doctype html>\n<html>\n <head>\n  <title>%s</title>\n </head>\n <body>\n' 'The Black Knight - Crude web interface'
printf ' <h2>The frontdoor controller (%s) is ' "$BLACKKNIGHTIO"
test -n "$BLACKKNIGHTIO" && $BLACKKNIGHTIO running || printf 'NOT '
printf 'running.</h2><br />\n'
printf "  <button onclick=\"window.location.href='%s?beep'\"> Beep the buzzer </button><br />\n" "$ME"
printf '  <h3>Door open request</h3>\n'
printf '  Use your HSBXL MediaWiki credentials to open the door<br />\n'
printf "  <form method=\"post\" action=\"%s\" enctype=\"x-www-form-urlencoded\">\n" "$ME"
printf "   Username: <input type=\"text\" size=20 name=\"user\">%s<br />\n" "$MISSINGUSERTEXT"
printf "   Password: <input type=\"password\" size=20 name=\"pass\">%s<br />\n" "$MISSINGPASSTEXT"
printf "   <input type=\"submit\" value=\"Open\">\n"
printf '  </form>\n'

#env|while read l ; do echo "$l<br />"; done
#echo "postdata=$POSTDATA<br />"


#footer
printf ' </body>\n</html>\n'
