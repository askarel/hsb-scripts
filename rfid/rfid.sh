#!/bin/bash
#
#	LDAP based RFID database
#
#	(c) 2017 Frederic Pasteleurs <frederic@askarel.be>
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


# CONFIG AREA ##############################################

READER="ACS ACR122U PICC Interface 00 00"
LDAPSERVER='vps318480.hsbxl.be'
BASEDN='dc=hsbxl,dc=be'

#############################################################
ME="$(basename $0)"
PAUSEFILE="/tmp/RFID.register"

# Function to call when we bail out
# Parameter 1: text to output
# Parameter 2: exitcode when leaving. Set to 1 if empty
die()
{
    echo "$ME: $1. Exit" >&2
    test -n "$2" && exit $2
    exit 1
}

# Make sure we remove the pause file when bailing out
cleanup()
{
    rm -f "$PAUSEFILE"
    exit
} 

trap cleanup EXIT

gettaghash()
{
    unset HASH # make sure variable is empty
    echo "Waiting for RFID card..." >&2
    touch $PAUSEFILE
    while test -z "$HASH"; do
	ATRHASH="$(echo "reset" | scriptor -r "$READER" 2> /dev/null | tail -n 1 | md5sum | cut -d ' ' -f 1)"
	if [ "$ATRHASH" != 'd41d8cd98f00b204e9800998ecf8427e' ] ; then # d41d8cd98f00b204e9800998ecf8427e is the empty string hash
		# Ask the card UID and hash the result (i don't care about the garbage)
		CARDHASH="$(echo 'ffca000000'|scriptor -r "$READER" 2> /dev/null|tail -n 1 | md5sum | cut -d ' ' -f 1)"
		if [ "$ATRHASH" != 'd41d8cd98f00b204e9800998ecf8427e' ] ; then # d41d8cd98f00b204e9800998ecf8427e is the empty string hash
		    HASH="$(echo -n "$CARDHASH $ATRHASH"| md5sum | cut -d ' ' -f 1)"
		fi
	else
	    unset ATRHASH
	fi
    done
    # Wait until the card is gone
    while test -z "$CARDREMOVED"; do
	echo "reset"|scriptor > /dev/null 2>&1
	test "${PIPESTATUS[1]}" -ne "0" && CARDREMOVED="yes"
    done
    rm $PAUSEFILE
    echo "$HASH"
}

########################################################################################################

helptext()
{
cat << HELPTEXT
Usage: $ME [addtag|gettaginfo|revoketag|listusers|listusertags|listalltags|edituser|showlog]

    tagmanager <username>	Start interactive tag manager
    listusertags user		List all tags used by user
    gettaghash		Show the hash of an RFID tag (requires working RFID reader)
    dumpflat		Dump a flat text version of the valid tags data (for embedded use)

HELPTEXT
exit 1
}

# Add tag to user
# Parameter 1: LDAP server to use
# Parameter 2: Bind DN (user DN or access controller DN
# Parameter 3: Password for above DN
# Parameter 4: tag hash (if known)
addtag()
{
    test -z "$1" && die "Specify LDAP server to use"
    test -z "$2" && die "Specify user DN (example: uid=john_doe,ou=users,dc=hsbxl,dc=be)"
    test -z "$3" && die "Specify password for account '$2'"
}

# Dump a list of tags used by specified user
# Parameter 1: LDAP server to use
# Parameter 2: Bind DN (user DN or access controller DN
# Parameter 3: Password for above DN
# Parameter 4: User DN to dump, Use bind DN (parameter 2) if empty
# output: list of tags for specified user DN 
dumpusertags()
{
    test -z "$1" && die "Specify LDAP server to use"
    test -z "$2" && die "Specify user or access controller DN (example: uid=door1,ou=machines,dc=hsbxl,dc=be)"
    test -z "$3" && die "Specify password for account '$2'"
    local USERDN="$4"
    test -z "$4" && USERDN="$2"
    ldapsearch -o ldif-wrap=no -x -h "$1" -D "$2" -w "$3" -b "$USERDN" -LLL 'x-hsbxl-RFIDid' | grep 'x-hsbxl-RFIDid' | cut -d ' ' -f 2-
}

# Manage user tags
# Parameter 1: LDAP server to use
# Parameter 2: username
# parameter 3: password
managetags()
{
    test -z "$1" && die "Specify LDAP server to use"
    test -z "$2" && die "Specify user name"
    test -z "$3" && die "Specify password for account '$2'"
#    tput smcup
#    clear
    TAGSARRAY=( $(dumpusertags "$1" "uid=$2,ou=users,$BASEDN" "$3" ) )
    printf "Index|Scanned|ver.|Createtime    |Validity start|Validity end  |Tag hash                        |Status  |Nickname\n"
    for (( i=0 ; i<${#TAGSARRAY[@]} ; i++ )) do 
	for (( j=1 ; j<8 ; j++ )) do 
	    SPLITTAGS[$(( $j - 1 ))]="$( cut -d ';' -f $j <<< "${TAGSARRAY[$i]}" )"
	    test -z "${SPLITTAGS[$(( $j - 1 ))]}" && SPLITTAGS[$(( $j - 1 ))]=0
	done
	printf '  %-3s| [ %-2s] | %-3s|%-14s|%-14s|%-14s|%-32s|%-8s|%s\n' "$i" 0 "${SPLITTAGS[0]}" "$(date --iso-8601 --date="@${SPLITTAGS[1]}" 2> /dev/null)" "$(date --iso-8601 --date="@${SPLITTAGS[2]}" 2> /dev/null)" "$(date --iso-8601 --date="@${SPLITTAGS[3]}" 2> /dev/null)" "${SPLITTAGS[4]}" "${SPLITTAGS[5]}" "${SPLITTAGS[6]}"
#	echo "  $i		${TAGSARRAY[$i]}"  "${SPLITTAGS[1]}"
    done
#    read
#    tput rmcup
}

# Dump a flat text file for the access controller
# Parameter 1: LDAP server to use
# Parameter 2: access controller DN
# Parameter 3: access controller password
# Parameter 4: access controller group
# Return: text list of allowed tags
dumpflat()
{
    test -z "$1" && die "Specify LDAP server to use"
    test -z "$2" && die "Specify access controller DN (example: uid=door1,ou=machines,dc=hsbxl,dc=be)"
    test -z "$3" && die "Specify password for account '$2'"
    SEARCHFILTER="(&(objectClass=groupOfNames))"
#    echo "searchfilter: $SEARCHFILTER"
    ldapsearch -o ldif-wrap=no -x -h "$1" -D "$2" -w "$3" -b "cn=user_tags,$2" -LLL "$SEARCHFILTER" | grep '^member' | cut -d ' ' -f 2- \
	| while read line; do
	    ldapsearch -o ldif-wrap=no -x -h "$1" -D "$2" -w "$3" -b "cn=Members,ou=groups,$BASEDN" -LLL member | grep '^member' | cut -d ' ' -f 2- \
		| while read line2; do
#		    test "$line" == "$line2" && echo $line
		    test "$line" == "$line2" && dumpusertags "$1" "$2" "$3" "$line"
		done
	done
}

# Format incoming CSV to a tab delimited output for version 1 controllers
formattoV1()
{
    while read line3; do
	test "$(cut -d ';' -f 1 <<< "$line3" )" == 'v1' && awk -e  'BEGIN {FS=";"; OFS="\t" ;} { if (!$4) {print $5,$3,"NULL","0","0",$7} else {print $5,$3,$4,"0","0",$7 } }' <<< "$line3"
    done
}

test -x "$(which ldapsearch)" || die "ldapsearch not found or not installed (apt-get install ldapscripts)"
test -x "$(which scriptor)" || die "scriptor not found or not installed (apt-get install pcsc-tools)"

case "$1" in
    'tagmanager')
	SCRIPT_USERNAME="$2"
	SCRIPT_PASSWORD="$3"
	test -z "$SCRIPT_USERNAME" && read -p 'Username: ' SCRIPT_USERNAME
	test -z "$SCRIPT_PASSWORD" && read -s -p 'Password: ' SCRIPT_PASSWORD
	echo
	managetags "$LDAPSERVER"  "$SCRIPT_USERNAME" "$SCRIPT_PASSWORD" "$4" "$5" "$6"
	;;
    "listusertags")
	dumpusertags "$LDAPSERVER" "$2" "$3" "$4" "$5" "$6"
	;;
    "dumpflat")
	dumpflat "$LDAPSERVER" "$2" "$3" "$4" "$5" | formattoV1
	;;
    'debugfunc')
	dumpusertags "$LDAPSERVER" "$2" "$3" "$4" "$5" "$6"
	;;
    'gettaghash')
	gettaghash
	;;
    *)
	helptext
	;;
esac
