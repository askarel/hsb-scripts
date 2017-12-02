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
Usage: $ME [tagmanager|password|listusertags|gettaghash|dumpflat]

    tagmanager <username>	Start interactive tag manager
    password <username>		Change password for specified user
    listusertags user		List all tags used by user
    gettaghash			Show the hash of an RFID tag (requires working RFID reader)
    dumpflat			Dump a flat text version of the valid tags data (for embedded use)

HELPTEXT
exit 1
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

# Dump a user-friendly list of tags used by specified user
# Parameter 1: Index of scanned tag
# Parameter 2: Array of valid tags
# output: user-readable list of tags for specified user DN 
friendlyusertags()
{
    local INDEX="$1"
    shift
    local ARR=( "$@" )
    local i j
    printf "Index|Scanned|ver.|Createtime    |Validity start|Validity end  |Tag hash                        |Status  |Nickname\n"
    for (( i=0 ; i<${#ARR[@]} ; i++ )) do 
	for (( j=1 ; j<8 ; j++ )) do 
	test -n "$INDEX" -a "$i" == "$INDEX" && TAGMARK='>' || TAGMARK=''
	    SPLITTAGS[$(( $j - 1 ))]="$( cut -d ';' -f $j <<< "${ARR[$i]}" )"
	    test -z "${SPLITTAGS[$(( $j - 1 ))]}" && SPLITTAGS[$(( $j - 1 ))]=0
	done
	test -n "${ARR[$i]}" && printf '  %-3s| [ %-2s] | %-3s|%-14s|%-14s|%-14s|%-32s|%-8s|%s\n' "$i" "$TAGMARK" "${SPLITTAGS[0]}" "$(date --iso-8601 --date="@${SPLITTAGS[1]}" 2> /dev/null)" "$(date --iso-8601 --date="@${SPLITTAGS[2]}" 2> /dev/null)" "$(date --iso-8601 --date="@${SPLITTAGS[3]}" 2> /dev/null)" "${SPLITTAGS[4]}" "${SPLITTAGS[5]}" "${SPLITTAGS[6]}"
#	echo "  $i		${TAGSARRAY[$i]}"  "${SPLITTAGS[1]}"
    done
}

# Generate LDIF to update RFID tags
# Parameter 1: User DN
# Parameter 2: array of valid tags
# output: LDIF data to be submitted to LDAP server
ldiftags()
{
    local DN="$1"
    shift
    local ARR=( "$@" )
    local i
    printf 'dn: %s\nchangetype: modify\ndelete: x-hsbxl-RFIDid\n' "$DN"
    for (( i=0 ; i<${#ARR[@]} ; i++ )) do 
	test -n "${ARR[$i]}" && printf '\ndn: %s\nchangetype: modify\nadd: x-hsbxl-RFIDid\nx-hsbxl-RFIDid: %s\n' "$DN" "${ARR[$i]}"
    done
}

# Change password for user
# Parameter 1: LDAP server to use
# Parameter 2: User name
# Parameter 3: password for specified DN
ldap_password()
{
    test -z "$1" && die "Specify LDAP server to use"
    test -z "$2" && die "Specify user name"
    local USERDN="uid=$2,ou=users,$BASEDN"
    ldappasswd -H "ldap://$1" -x -D "$USERDN" -W -S
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
    local i SCANNEDTAG USERDN="uid=$2,ou=users,$BASEDN"
    TAGSARRAY=( $(dumpusertags "$1" "$USERDN" "$3" ) )
    OLDDATAHASH="$( md5sum <<< "${TAGSARRAY[*]}" )" # To ask if the user want to save the data
#    tput smcup
#    clear
    while true; do
	case "$LOCALCOMMAND" in
	'q'|'Q') # Quit command
	    if [ "$OLDDATAHASH" != "$( md5sum <<< "${TAGSARRAY[*]}" )" ]; then
		read -n 1 -r -p "Data changed. Do you want to commit to LDAP server (y/n)? [N]: " COMMITYESNO
		test "$COMMITYESNO" = 'Y' -o "$COMMITYESNO" = 'y' && ldiftags "$USERDN" "${TAGSARRAY[@]}" | ldapadd -c -h "$1" -D "$USERDN" -w "$3"
	    fi
#	    tput rmcup
	    exit
	    ;;
	'c'|'C') # Commit command
	    unset LOCALCOMMAND
	    if [ "$OLDDATAHASH" != "$( md5sum <<< "${TAGSARRAY[*]}" )" ]; then
		ldiftags "$USERDN" "${TAGSARRAY[@]}" | ldapadd -c -h "$1" -D "$USERDN" -w "$3"
		test $? -eq 0 && OLDDATAHASH="$( md5sum <<< "${TAGSARRAY[*]}" )" # To ask if the user want to save the data
	    else
		echo 'There are no changes to commit'
	    fi
	    ;;
	'd'|'D') # Delete command
	    unset LOCALCOMMAND
	    test -z "$LOCALPARAMETER" && read -p 'Specify tag index to delete: ' LOCALPARAMETER
	    test -n "$LOCALPARAMETER" && TAGSARRAY["$LOCALPARAMETER"]=''
	    unset LOCALPARAMETER
	    ;;
	'e'|'E') # Edit command
	    unset LOCALCOMMAND
	    test -z "$LOCALPARAMETER" && read -p 'Specify tag index to edit: ' LOCALPARAMETER
#	    read -p "Subactions: validity (s)tart, validity (e)nd, tag stat(u)s, (n)ickname, (q)uit :" LOCALSUBCOMMAND LOCALSUBPARAMETER
#	    while true; do
#		case "$LOCALSUBCOMMAND" in
#		    's'|'S') # Validity start
#			test -z "$LOCALSUBPARAMETER" && read -p 'Specify validity start date (YYYY-MM-DD): ' LOCALSUBPARAMETER
#		    ;;
#		    'e'|'E') # Validity end
#			test -z "$LOCALSUBPARAMETER" && read -p 'Specify validity end date (YYYY-MM-DD): ' LOCALSUBPARAMETER
#		    ;;
#		    'u'|'U') # Tag status
#			test -z "$LOCALSUBPARAMETER" && read -p 'Specify tag status: ' LOCALSUBPARAMETER
#		    ;;
#		    'n'|'N') # Nickname
#			test -z "$LOCALSUBPARAMETER" && read -p 'Specify name to be spoken (keep empty for silence): ' LOCALSUBPARAMETER
#		    ;;
#		    *)
#		    break
#		    ;;
#		esac
#	    done
	    echo "TODO: this is non functional at the moment."
	    unset LOCALPARAMETER LOCALSUBCOMMAND LOCALSUBPARAMETER
	    ;;
	'a'|'A') # Add command
	    unset LOCALCOMMAND
	    test -z "$SCANNEDTAG" && SCANNEDTAG="$(gettaghash)"
	    TAGSARRAY[${#TAGSARRAY[@]}]="v1;$(date '+%s');$(date '+%s');;$SCANNEDTAG;;$2"
	    unset LOCALPARAMETER
	    ;;
	's'|'S') # Scan tag command
	    unset LOCALCOMMAND TAGGEDENTRY
	    SCANNEDTAG="$(gettaghash)"
	    for (( i=0 ; i<${#TAGSARRAY[@]} ; i++ )) do 
		if [ "$( cut -d ';' -f 5 <<< "${TAGSARRAY[$i]}")" = "$SCANNEDTAG" ]; then
		    TAGGEDENTRY="$i"
		    break
		fi
	    test -z "$TAGGEDENTRY" && TAGGEDENTRY='NOTFOUND'
	    done
	    ;;
	*)
	    friendlyusertags "$TAGGEDENTRY" "${TAGSARRAY[@]}"
	    echo
	    test "$TAGGEDENTRY" = 'NOTFOUND' && printf "Tag '%s' not found.\n" "$SCANNEDTAG"
	    read -p "Actions: (a)dd tag, (d)elete tag, (s)can tag, (e)dit tag, (c)ommit, (q)uit :" LOCALCOMMAND LOCALPARAMETER
	    ;;
	esac
    done
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
	test "$(cut -d ';' -f 1 <<< "$line3" )" == 'v1' && \
	    awk -e  'BEGIN {FS=";"; OFS="\t" ;} $3~/^[0-9]+$/ && ( $4~/^[0-9]+$/ || $4~/^$/ ) { if (!$4) {print $5,$3,"NULL","0","0",$7} else {print $5,$3,$4,"0","0",$7 } }' <<< "$line3"
    done
}

test -x "$(which ldapsearch)" || die "ldapsearch not found or not installed (apt-get install ldapscripts)"
test -x "$(which ldapadd)" || die "ldapadd not found or not installed (apt-get install ldapscripts)"
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
    'password')
	SCRIPT_USERNAME="$2"
	test -z "$SCRIPT_USERNAME" && read -p 'Username: ' SCRIPT_USERNAME
	ldap_password "$LDAPSERVER" "$SCRIPT_USERNAME"
	;;
    'gettaghash')
	gettaghash
	;;
    *)
	helptext
	;;
esac
