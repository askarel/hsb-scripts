#!/bin/bash

# 	Member list handler client for Hackerspace Brussels 
#	(c) 2016 Frederic Pasteleurs <frederic@askarel.be>
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

readonly ME="$(basename "$0" .sh)"
readonly MYDIR="$(dirname "$0")"
readonly CONFIGFILE="$ME.conf"
# Default path for the SQL files
readonly SQLDIR="$MYDIR/sql/"
# Default path to LDAP custom schema
readonly LDAPSCHEMADIR="$MYDIR/ldap-schema/"
# Default path to mail templates
readonly TEMPLATEDIR="$MYDIR/templates"
readonly GPGHOME="$MYDIR/.gnupg"
#readonly DEBUGGING=true
# Fields required for LDAP server
declare -A -r LDAP_FIELDS=( [uid]='Nickname/username *' [sn]='Family Name *' [givenname]='First name *' [mail]='Email address *' 
			[preferredlanguage]='preferred language' [homephone]='Phone number' [description]='Why do you want to become member *'
			[x-hsbxl-membershiprequested]='Membership requested #' [x-hsbxl-votingrequested]='Do you want to vote at the general assembly #'
			[x-hsbxl-socialTariff]='Do you require the social tariff #' [x-hsbxl-sshpubkey]='SSH Public key' [x-hsbxl-pgpPubKey]='PGP Public key' )
declare -A LDAP_REPLY

############### <FUNCTIONS> ###############
# Function to call when we bail out
die()
{
    echo "$ME: $1. Exit" >&2
    test -n "$2" && exit $2
    exit 1
}

# Run a SQL command as user (new style)
# Parameter 1: username
# Parameter 2: password
# Parameter 3: SQL query. If it's a valid file, run it's content
# Parameter 4: if set, do not bail out on error
# output: tab-separated data
# exit code 0: request successful
user_runsql()
{
    test -z "$1" && die "Empty username"
    test -z "$2" && die "Empty password"
    test -z "$3" && die "Empty SQL request"
    local SQPROG='echo'
    test -f "$3" && SQPROG='cat'
    case "$DBTYPE" in
	'mysql')
	    if [ -z "$4" ]; then $SQPROG "$3" | mysql -h"$SQLHOST" -u"$1" -p"$2" -D"$SQLDB" -s --skip-column-names  || die "Failed query: '$3'" # Fix your junk !
			    else $SQPROG "$3" | mysql -h"$SQLHOST" -u"$1" -p"$2" -D"$SQLDB" -s --skip-column-names  2>&1 # We want the error
	    fi
	;;
	'postgres')
	    die 'PostgresQL is not implemented (yet)'
	;;
	*) die "Unknown database type: $DBTYPE"
	;;
    esac
}

# run a SQL command. (old style)
# Parameter 1: SQL request. If it's a valid file, run it's content
# Parameter 2: if set, do not bail out on error
# output: tab-separated data
# exit code 0: request successful
runsql()
{
    user_runsql "$SQLUSER" "$SQLPASS" "$1" "$2"
#    test -z "$1" && die "Empty SQL request"
#    local SQPROG='echo'
#    test -f "$1" && SQPROG='cat'
#    if [ -z "$2" ]; then $SQPROG "$1" | mysql -h"$SQLHOST" -u"$SQLUSER" -p"$SQLPASS" -D"$SQLDB" -s --skip-column-names  || die "Failed query: '$1'" # Fix your junk !
#		    else $SQPROG "$1" | mysql -h"$SQLHOST" -u"$SQLUSER" -p"$SQLPASS" -D"$SQLDB" -s --skip-column-names  2>&1 # We want the error
#    fi
}

# This will check that all binaries needed are available
check_prerequisites()
{
    while test -n "$1"; do
	which "$1" > /dev/null || die "Command '$1' not found in path ($PATH)"
	shift
    done
}

# Send the data on STDIN by e-mail.
# Parameter 1: sender address
# Parameter 2: receiver address
# Parameter 3: optional GnuPG key ID. If the key is usable, the mail will be encrypted before sending
# First line will be pasted as subject line
# This function will send e-mail using the local SMTP server
do_mail()
{
    test -z "$1" && die 'No sender address specified'
    test -z "$2" && die 'No receiver address specified'
    local SUBJECTLINE
    # This will eat the first line of stdin
    read SUBJECTLINE
    if [ -z "$DEBUGGING" ] ; then 
	if gpg --no-permission-warning --homedir "$GPGHOME" --fingerprint "$3" > /dev/null 2>&1; then # Is key usable ?
	    gpg --no-permission-warning --homedir "$GPGHOME" --encrypt --armor --batch --always-trust --recipient "$3" | bsd-mailx -a "From: $1" -s "$ORGNAME - $SUBJECTLINE" "$2"
	else # Invalid or non-existent key: send cleartext.
	    bsd-mailx -a "From: $1" -s "$ORGNAME - $SUBJECTLINE" "$2"
	fi
    else 
	echo "DEBUG: From: '$1' To: '$2' Suject: '$ORGNAME - $SUBJECTLINE'" 
	cat
    fi
}

# Show the requested template and the footer
# Parameter 1: language requested
# Parameter 2: template name
templatecat()
{
    local mytemplate myfooter
    test -d "$TEMPLATEDIR" || die "Templates directory '$TEMPLATEDIR' does not exist"
    # Fall back to default language if not exists
    test -f "$TEMPLATEDIR/$1/$2" && mytemplate="$TEMPLATEDIR/$1/$2" || mytemplate="$TEMPLATEDIR/$DEFAULT_LANGUAGE/$2"
    test -f "$TEMPLATEDIR/$1/footer.txt" && myfooter="$TEMPLATEDIR/$1/footer.txt" || myfooter="$TEMPLATEDIR/$DEFAULT_LANGUAGE/footer.txt"
    test -f "$mytemplate" || die "Template '$mytemplate' not found"
    # Variables that needs substitution
    export MEMBERSHIP_STRUCTUREDCOMM BAR_STRUCTUREDCOMM STRUCTUREDCOMM BANKACCOUNT CURRENCY YEARLYFEE MONTHLYFEE ORGNAME JOINREASON PASSWORD BIRTHDATE FIRSTNAME NICKNAME EXPIRYDATE LEAVEREASON QUORUM
    cat "$mytemplate" | envsubst
    test -f "$myfooter" && cat "$myfooter" | envsubst
}

# Return the DN of specified user
# Parameter 1: LDAP server
# Parameter 2: Bind DN
# Parameter 3: Password for bind DN
# Parameter 4: Base DN
# Parameter 5: Username to search for
# Output: list of existing DNs. Nothing if no match.
ldap_getUserDN()
{
    ldapsearch -o ldif-wrap=no -LLL -h "$1" -D "$2" -w "$3" -b "$4" "(uid=$5)" dn
}

# NEED REPAIR
# This function is a fucking mess ! Being clever is too much. :-(
# Once we go full LDAP, this will disappear: add user from LDAP server
addperson()
{
    local REQUESTED_FIELDS=(lang firstname name nickname phonenumber emailaddress birthdate openpgpkeyid machinestate_data)
    local REQUESTED_FIELDS_DESC=('Preferred language' 'Firstname' 'Family name' 'Nickname' 'phone number' 'Email address' 'Birth date' 
				'OpenPGP key ID' "informations (free text, use '|' to finish)\n")
    local -a REPLY_FIELD
    local SQL_QUERY="insert into person (entrydate, $(tr ' ' ',' <<< "${REQUESTED_FIELDS[@]}"), passwordhash, ldaphash, machinestate, machinestate_expiration_date) values ( \"$(date '+%Y-%m-%d')\", "
    local OPS3="$PS3"
    local persontype='members'
    PS3="Select person type to add (default: $persontype): "
    select persontype in members cohabitants guest landlord contractor; do
	test -n "$persontype" && break
    done
    PS3="$OPS3"
    echo "Adding a new $persontype to the system..."
    PASSWORD="$(pwgen 20 1)"
    for (( i=0; i<${#REQUESTED_FIELDS[@]}; i++ )) do
	printf '[%s/%s] %20s: ' "$(( $i + 1 ))" "${#REQUESTED_FIELDS[@]}" "${REQUESTED_FIELDS_DESC[$i]}"
	test $i -lt  $(( ${#REQUESTED_FIELDS[@]} - 1 )) && read REPLY_FIELD[$i] || read -d '|' REPLY_FIELD[$i]
	REPLY_FIELD[$i]="$(sed -e "s/[\\']/\\\\&/g" <<< "${REPLY_FIELD[$i]}")" # Escape quote (avoids SQL injection)
	SQL_QUERY="$SQL_QUERY '${REPLY_FIELD[$i]}',"
    done
    # Key specified ? Import it.
    test -n  "${REPLY_FIELD[7]}" && gpg --no-permission-warning --homedir "$GPGHOME" --keyserver hkp://keys.gnupg.net --recv-keys "${REPLY_FIELD[7]}"

    local CRYPTPASSWORD="$(mkpasswd -m sha-512 -s <<< "$PASSWORD")"
    local LDAPHASH="$(/usr/sbin/slappasswd -s "$PASSWORD")"
    # Empty nickname field ?
    test -z "${REPLY_FIELD[3]}" && REPLY_FIELD[3]="$(tr -s ' ' '_' <<< "${REPLY_FIELD[1]}_${REPLY_FIELD[2]}")"
    case "$persontype" in
	'members')
	    SQL_QUERY="$SQL_QUERY '$CRYPTPASSWORD', '$LDAPHASH', 'MEMBER_MANUALLY_ENTERED', date_add(now(), interval 1 month) );"
	    ;;
	'cohabitants')
	    SQL_QUERY="$SQL_QUERY '$CRYPTPASSWORD', '$LDAPHASH', 'COHABITANT_ENTERED', NULL );"
	    ;;
	'guest')
	    SQL_QUERY="$SQL_QUERY '$CRYPTPASSWORD', '$LDAPHASH', 'GUEST_ENTERED', NULL );"
	    ;;
	'landlord')
	    SQL_QUERY="$SQL_QUERY '$CRYPTPASSWORD', '$LDAPHASH', 'LANDLORD_ENTERED', NULL );"
	    ;;
	'contractor')
	    SQL_QUERY="$SQL_QUERY '$CRYPTPASSWORD', '$LDAPHASH', 'CONTRACTOR_ENTERED', NULL );"
	    ;;
    esac
#    echo "$SQL_QUERY"
    USER_UID="$(runsql 'select count(id)+1005 from person')"
    runsql "$SQL_QUERY" && echo "$ME: Added $persontype to database."
#    runsql "insert into member_groups (member_id, group_id) values ( (select max(id) from person),(select bit_id from hsb_groups where shortdesc like '$persontype') )" && echo "$ME: Added to group $persontype"
    test "$persontype" = 'member' && STRUCTUREDCOMM="$(account_create "MEMBERSHIP" "$(lookup_person_id "${REPLY_FIELD[5]}")")" #"
    # WARNING: Shitty code below:
    USERDN="uid=${REPLY_FIELD[3]},ou=users,$BASEDN"
    echo "dn: $USERDN"
    echo "cn: ${REPLY_FIELD[1]} ${REPLY_FIELD[2]}"
    echo "gidnumber: 503"
    echo "givenname: ${REPLY_FIELD[1]}"
    echo "homedirectory: /home/users/${REPLY_FIELD[3]}"
    test -n "${REPLY_FIELD[4]}" && echo "homephone: ${REPLY_FIELD[4]}"
    echo "mail: ${REPLY_FIELD[5]}"
    echo "objectclass: inetOrgPerson"
    echo "objectclass: posixAccount"
    echo "objectclass: top"
    echo "objectclass: x-hsbxl-person"
    echo "objectclass: x-hsbxl-structuredcomm-addon"
    test -n "${REPLY_FIELD[0]}" && echo "${REPLY_FIELD[0]}"
    echo "sn: ${REPLY_FIELD[2]}"
    echo "uid: ${REPLY_FIELD[3]}"
    echo "userpassword: $LDAPHASH"
    test "$persontype" = 'member' && echo "x-hsbxl-membershiprequested: TRUE"
    test "$persontype" = 'member' && echo "x-hsbxl-membershipstructcomm: $STRUCTUREDCOMM"
    echo "uidnumber: $USER_UID"
    test -n "$DESCRIPTION" && echo "description: $DESCRIPTION"
    echo ""

    # If we're here, we have successfully inserted person data
#    STRUCTUREDCOMM="$(runsql 'select structuredcomm from person order by id desc limit 1')"
    EXPIRYDATE="$(runsql 'select machinestate_expiration_date from person order by id desc limit 1')"
    FIRSTNAME="${REPLY_FIELD[1]}"
    NICKNAME="${REPLY_FIELD[3]}"
    JOINREASON="${REPLY_FIELD[8]}"
    templatecat "${REPLY_FIELD[0]}" "${ME}.sh_person_add_${persontype}.txt" | do_mail "$MAILFROM" "${REPLY_FIELD[5]}" "${REPLY_FIELD[7]}"
}

# Attempt to rewrite above function in a cleaner way.
# Create a new LDAP user/member
# Parameter 1: user DN to query/update the LDAP
# Parameter 2: Password for above user
# Parameter 3: User DN to create. If the string does not look like a DN, transform it into one.
addperson2ldap()
{
    echo
}

# Ask a bunch of questions to user
# Parameter 1: *name* of the variable array containing the prompts
# Parameter 2: *name* of the variable array to fill
askquestions()
{
	declare -A PROMPTS
	eval "PROMPTS=( \${$1} )"
	for i in ${PROMPTS[@]} ; do
#	    echo "\$1[$i]=${LDAP_REPLY[$i]}"
	    echo "$i"
#	    echo "${!LDAP_FIELDS[@]}"
	done
}


# Lookup person ID
# Parameter 1: nickname or email address
# Output: valid person ID from database
# Bail out if requested data is not found
function lookup_person_id()
{
    test -z "$1" && die 'Spefify person e-mail address or nickname'
    case "$(runsql "select count(id) from person where nickname like '$1' or emailaddress like '$1'")" in #"
	'0')
	    die "No match for user/email '$1'"
	    ;;
	'1')
	    runsql "select id from person where nickname like '$1' or emailaddress like '$1'"
	    ;;
	*)
	    die "Ambiguous result: multiple matches for user/email '$1'"
	    ;;
    esac
}

# Modify data for an existing user
# Parameter 1: user to modify (e-mail address or nickname)
# Parameter 2: name of field to modify
# Parameter 3: field data
# Once we go full LDAP, this will disappear: modify user from phpldapadmin
modifyperson()
{
    local SELECTED_FIELD
    test -z "$1" && die "Specify the nickname or e-mail address of the person that need to be modified"
    local PERSONID="$(lookup_person_id "$1")"
    test -z "$PERSONID" && die "No match found for user '$1'"
    local AVAILABLE_FIELDS="$(runsql 'desc person'|cut -f 1|grep -v 'passwordhash'|tr "\\n" ' ' )"
    test -z "$2" && die "Specify database field to modify. Available fields: ${AVAILABLE_FIELDS}"
    for i in $AVAILABLE_FIELDS; do
	test "$i" = "$2" && SELECTED_FIELD="$i"
    done
    test -z "$SELECTED_FIELD" && die "Field '$2' does not exist. Available fields: $(tr ' ' ',' <<< "$AVAILABLE_FIELDS")"
    test -z "$3" && die "Specify the new data"
    runsql "update person set $SELECTED_FIELD='$3' where id=$PERSONID" && die "Modification Successful" 0
}

# Send a new password for specified user
# Parameter 1: user to change password for
changepassword()
{
    test -z "$1" && die "Specify the nickname or e-mail address of the person that need a new password"
    local PERSONID="$(lookup_person_id "$1")"
    local PASSWORD="$(pwgen 20 1)"
    test -z "$PERSONID" && die "No match found for user '$1'"
    local MYLANG="$(runsql "select lang from person where id=$PERSONID")"
    local EMAILADDRESS="$(runsql "select emailaddress from person where id=$PERSONID")"
    local FIRSTNAME="$(runsql "select firstname from person where id=$PERSONID")"
    local GPGID="$(runsql "select openpgpkeyid from person where id=$PERSONID")"
    local CRYPTPASSWORD="$(mkpasswd -m sha-512 -s <<< "$PASSWORD")"
    local LDAPHASH="$(/usr/sbin/slappasswd -s "$PASSWORD")"
    if runsql "update person set passwordhash='$CRYPTPASSWORD', ldaphash='$LDAPHASH' where id=$PERSONID" ; then
	templatecat "$MYLANG" "$ME.sh_person_changepassword.txt" |  do_mail "$MAILFROM" "$EMAILADDRESS" "$GPGID"
    fi
}

# Send a new password for specified user
# Parameter 1: user DN to query the LDAP
# Parameter 2: Password for above user
# Parameter 3: User DN to change password for. If the string does not look like a DN, 
changeLdapPassword()
{
    echo
}

# Re-send the payment infos for specified user
# Parameter 1: user to re-send infos for
resendinfos()
{
    test -z "$1" && die "Specify the nickname or e-mail address of the person that need a reminder"
    local PERSONID="$(lookup_person_id "$1")"
    test -z "$PERSONID" && die "No match found for user '$1'"
    local MYLANG="$(runsql "select lang from person where id=$PERSONID")"
    local EMAILADDRESS="$(runsql "select emailaddress from person where id=$PERSONID")"
    local FIRSTNAME="$(runsql "select firstname from person where id=$PERSONID")"
    local GPGID="$(runsql "select openpgpkeyid from person where id=$PERSONID")"
#    local STRUCTUREDCOMM="$(runsql "select structuredcomm from person where id=$PERSONID")"
    local STRUCTUREDCOMM="$(runsql "select structuredcomm from internal_accounts where account_type like 'MEMBERSHIP' and owner_id=$PERSONID")"
    templatecat "$MYLANG" "$ME.sh_person_resendinfos.txt" |  do_mail "$MAILFROM" "$EMAILADDRESS" "$GPGID"
}

# Cancel membership for specified member
# parameter 1: member to expel
membercancel()
{
    test -z "$1" && die "Specify the nickname or e-mail address of the person that need to be terminated"
    local PERSONID="$(lookup_person_id "$1")"
    test -z "$PERSONID" && die "No match found for user '$1'"
    test "$(runsql "select machinestate from person where id=$PERSONID")" = 'MEMBERSHIP_CANCELLED' && die 'Membership already cancelled'
    local MYLANG="$(runsql "select lang from person where id=$PERSONID")"
    local EMAILADDRESS="$(runsql "select emailaddress from person where id=$PERSONID")"
    local FIRSTNAME="$(runsql "select firstname from person where id=$PERSONID")"
    local NAME="$(runsql "select name from person where id=$PERSONID")"
    local GPGID="$(runsql "select openpgpkeyid from person where id=$PERSONID")"
#    local STRUCTUREDCOMM="$(runsql "select structuredcomm from person where id=$PERSONID")"
    local STRUCTUREDCOMM="$(runsql "select structuredcomm from internal_accounts where account_type like 'MEMBERSHIP' and owner_id=$PERSONID")"
    local LEAVEREASON
    printf 'Please type the reason to cancel the membership of %s %s:' "$FIRSTNAME" "$NAME"
    read LEAVEREASON
    runsql "update person set machinestate='MEMBERSHIP_CANCELLED', machinestate_data='' where id=$PERSONID"
#    templatecat "$MYLANG" "$ME.sh_member_cancel.txt"
    templatecat "$MYLANG" "$ME.sh_member_cancel.txt" |  do_mail "$MAILFROM" "$EMAILADDRESS" "$GPGID"
}

# Reactivate membership for specified member
# parameter 1: member to reactivate
member_reactivate()
{
    test -z "$1" && die "Specify the nickname or e-mail address of the person that need to be reactivated"
    local PERSONID="$(lookup_person_id "$1")"
    test -z "$PERSONID" && die "No match found for user '$1'"
    test "$(runsql "select machinestate from person where id=$PERSONID")" != 'MEMBERSHIP_CANCELLED' && die 'Membership still active'
    local MYLANG="$(runsql "select lang from person where id=$PERSONID")"
    local EMAILADDRESS="$(runsql "select emailaddress from person where id=$PERSONID")"
    local FIRSTNAME="$(runsql "select firstname from person where id=$PERSONID")"
    local NAME="$(runsql "select name from person where id=$PERSONID")"
    local GPGID="$(runsql "select openpgpkeyid from person where id=$PERSONID")"
#    local STRUCTUREDCOMM="$(runsql "select structuredcomm from person where id=$PERSONID")"
    local STRUCTUREDCOMM="$(runsql "select structuredcomm from internal_accounts where account_type like 'MEMBERSHIP' and owner_id=$PERSONID")"
    runsql "update person set machinestate='MEMBERSHIP_ACTIVE', machinestate_data='' where id=$PERSONID"
#    templatecat "$MYLANG" "$ME.sh_member_reactivate.txt"
    templatecat "$MYLANG" "$ME.sh_member_reactivate.txt" |  do_mail "$MAILFROM" "$EMAILADDRESS" "$GPGID"
}

# Parameter 1: bank name (will be used to call the right parser)
# Parameter 2: bank statements filename
importbankcsv()
{
    test -z "$1" && die 'Specify bank name'
    test -z "$2" && die 'Specify file name to import'
    test -f "$2" || die "File '$2' does not exist or is not a regular file"
    local BANKPARSER="$(dirname "$0")/unicsv-$1.sh"
    test -x "$BANKPARSER" || die "Cannot find parser '$BANKPARSER' for bank '$1'"
    local TEMPFILE="$(mktemp /tmp/$ME.XXXXXXXXXXXXXXXXXXXXXXXX)"
    local IMPORTFILE="$BANKDIR/$(sha1sum "$2"|cut -d ' ' -f 1).${2##*.}"
    local FIELDS="$($BANKPARSER header | tr ';' ',')"

    if [ -f "$IMPORTFILE" ]; then
	read -p "File '$2' already imported. Local copy is in $IMPORTFILE. Do you want to continue ? [y/n]" -n 1 -r
	echo
	test "$REPLY" != 'y' -a "$REPLY" != 'Y' && die 'Aborted by user'
    fi
    cp "$2" "$IMPORTFILE"
    $BANKPARSER import "$2" > $TEMPFILE
    runsql "load data local infile '$TEMPFILE' into table moneymovements fields terminated by ';' enclosed by '\"' ignore 1 lines ($FIELDS) set date_val=STR_TO_DATE(@date_val,'%Y-%m-%d'),date_account=STR_TO_DATE(@date_account,'%Y-%m-%d')"
    rm "$TEMPFILE"
}

# This function will:
# - Fix the paying members that insist on not using the communication string
bank_fix_membership()
{
    for i in $(runsql "select id from person") ; do
	local THIS_COMM="$(runsql "select structuredcomm from internal_accounts where account_type like 'MEMBERSHIP' and owner_id=$PERSONID")"
	runsql "select fuckup_message from membership_fuckup_messages where member_id=$i"| while read FUCKUP ; do
	    runsql "update moneymovements set fix_fuckup_msg='$THIS_COMM' where message like '$FUCKUP'"
	done
    done
}

# Add a recurring fix, for people that insist on not using the structured message
# Parameter 1: person ID
# Parameter 2: recurring bad message
fix_multiple_payment_msg()
{
    local PERSONID="$(lookup_person_id "$1")"
    runsql "insert into membership_fuckup_messages (member_id, fuckup_message) values ($PERSONID, '$2')"
}

# List the payment from specified person
# Parameter 1: person ID
# Parameter 2: year. Current year if empty
list_person_payments()
{
    local THISYEAR="${2:-$(date '+%Y')}"
    local FIRSTNAME="$(runsql "select firstname from person where id=$1")"
    local NAME="$(runsql "select name from person where id=$1")"
    local MACHINESTATE="$(runsql "select machinestate from person where id=$1")"
    local ENTRYDATE="$(runsql "select entrydate from person where id=$1")"
    local EMAIL="$(runsql "select emailaddress from person where id=$1")"
    if test $(date '+%Y' -d "$ENTRYDATE") -le $THISYEAR ; then # Don't bother if the person was not member at the time
	for i in $(runsql "select structuredcomm from internal_accounts where owner_id=$1") ; do
	    printf ' -------- %s %s %s <%s> %s %s --------\n' "$ENTRYDATE" "$FIRSTNAME" "$NAME" "$EMAIL" "$MACHINESTATE" "$i"

	runsql "select date_val, this_account, amount, currency, message, fix_fuckup_msg from moneymovements where 
	    (message like '$i' or fix_fuckup_msg like '$i') and date_val between '$THISYEAR-01-01' and '$THISYEAR-12-31' order by date_val"
	done
    fi
}


massmail()
{
    test -z "$1" && die 'Spefify template to use'
    local MACHINESTATE='IMPORTED_MEMBER_INACTIVE'
    local QUORUM=$(runsql "select round(count(id)/2) from person where machinestate like '$MACHINESTATE'") #"
    if [ "$2" = 'go' ]; then
	    for P in $(runsql "select id from person where machinestate like '$MACHINESTATE'"); do
		local MYLANG="$(runsql "select lang from person where id=$P")"
		local EMAILADDRESS="$(runsql "select emailaddress from person where id=$P")"
		local FIRSTNAME="$(runsql "select firstname from person where id=$P")"
		local GPGID="$(runsql "select openpgpkeyid from person where id=$P")"
		templatecat "$MYLANG" "$1"
#		templatecat "$MYLANG" "$1" |  do_mail "$MAILFROM" "$EMAILADDRESS" "$GPGID"
	    done
	else
	    local P=$(runsql "select id from person where machinestate like '$MACHINESTATE' limit 1")
	    local MYLANG="$(runsql "select lang from person where id=$P")"
	    local EMAILADDRESS="$(runsql "select emailaddress from person where id=$P")"
	    local FIRSTNAME="$(runsql "select firstname from person where id=$P")"
	    templatecat "$MYLANG" "$1"
	    die '--- Dry run: use "go" to launch the mass mailing ---'
    fi
}

############################################# <BACKUP/RESTORE> #############################################

# Perform a backup of the database
# Parameter 1: destination filename
db_dump()
{
    test -z "$1" && die "Specify destination file for backup"
    mysqldump -h"$SQLHOST" -u"$SQLUSER" -p"$SQLPASS" --routines --triggers --hex-blob --add-drop-database --add-drop-table --flush-privileges --databases "$SQLDB" > "$1"
}

# Perform a restore of the database
# Parameter 1: source filename
db_restore()
{
    test -z "$1" && die "Specify source file to restore"
    test -f "$1" || die "Specified file does not exist"
    runsql "$1"
}

############################################# </BACKUP/RESTORE> #############################################

############################################# <INTERNAL ACCOUNTING> #############################################

# Create an internal account. This uses a belgian structured memo as identifier
# Parameter 1: account type
# Parameter 2: Person identifier (plain number are treated as MySQL integer, strings are treated as LDAP RDN, empty means anonymous account for drink tickets)
# Parameter 3: reference object (optional)
# Parameter 4: Creation date (optional)
# Returns: structured memo if success
account_create()
{
    test -z "$1" && die "account_create: missing account type"
    case "$2" in
	*[!0-9]*)
	    IDTYPE='owner_dn'
	    MYID="'$2'"
	    ;;
	'') # Anonymous
	    IDTYPE='owner_dn'
	    MYID="NULL"
	    ;;
	*)
	    IDTYPE='owner_id'
	    MYID="$2"
	    ;;
    esac
    NEWBECOMM="$(runsql 'select structuredcomm from internal_accounts where account_type is null limit 1')"
    test -z "$3" -a -z "$4" && SQLQUERY="update internal_accounts set in_use=1, account_type='$1', $IDTYPE=$MYID, created_on=CURRENT_TIMESTAMP where structuredcomm like '$NEWBECOMM'"
    test -n "$3" -a -z "$4" && SQLQUERY="update internal_accounts set in_use=1, account_type='$1', $IDTYPE=$MYID, created_on=CURRENT_TIMESTAMP, ref_dn='$3' where structuredcomm like '$NEWBECOMM'"
    test -z "$3" -a -n "$4" && SQLQUERY="update internal_accounts set in_use=1, account_type='$1', $IDTYPE=$MYID, created_on='$4' where structuredcomm like '$NEWBECOMM'"
    test -n "$3" -a -n "$4" && SQLQUERY="update internal_accounts set in_use=1, account_type='$1', $IDTYPE=$MYID, created_on='$4', ref_dn='$3' where structuredcomm like '$NEWBECOMM'"
    runsql "$SQLQUERY" a > /dev/null && echo "$NEWBECOMM"
}

# Pre-load an account with some cash
# Parameter 1: account ID (belgian structured message)
# Parameter 2: Point of sale identifier
# Parameter 3: amount to preload
# Parameter 4: payment message
preload_account()
{
    local ACCOUNTID="$(runsql "select structuredcomm from internal_accounts where structuredcomm like '$1'")"
    test -z "$ACCOUNTID" && die "Account $1 does not exist"
    test -z "$2" && die "Specify Point-of-sale ID"
    test -z "$3" && die "Specify amount to pre-load on account $ACCOUNTID"
    test -z "$4" && die "Specify message for account $ACCOUNTID"
    runsql "insert into moneymovements (date_val, date_account, amount, currency, other_account, this_account, message, transaction_id) VALUES 
	    (curdate(), curdate(), concat ('-', abs ($3)), '$CURRENCY', '$2', '$ACCOUNTID', '$4', concat ('INTERNAL/$ACCOUNTID/$2/', sha1(concat (current_timestamp(), '$4'))) )"
}

# Consume cash from account
# Parameter 1: account ID (belgian structured message)
# Parameter 2: Point of sale identifier
# Parameter 3: amount to consume
# Parameter 4: payment message
consume_account()
{
    local ACCOUNTID="$(runsql "select structuredcomm from internal_accounts where structuredcomm like '$1'")"
    test -z "$ACCOUNTID" && die "Account $1 does not exist"
    test -z "$2" && die "Specify Point-of-sale ID"
    test -z "$3" && die "Specify amount to consume from account $ACCOUNTID"
    test -z "$4" && die "Specify message for account $ACCOUNTID"
    runsql "insert into moneymovements (date_val, date_account, amount, currency, other_account, this_account, message, transaction_id) VALUES 
	    (curdate(), curdate(), abs($3), '$CURRENCY', '$2', '$ACCOUNTID', '$4', concat ('INTERNAL/$ACCOUNTID/$2/', sha1(concat (current_timestamp(), '$4'))) )"
}

# BUG: it does not check the balance before doing the transfer
# Transfer cash from account to account
# Parameter 1: source account ID
# PArameter 2: destination account ID
# Parameter 3: Point of sale identifier
# Parameter 4: amount to transfer
# Parameter 5: payment message
transfer_account()
{
    local SRC_ID="$(runsql "select structuredcomm from internal_accounts where structuredcomm like '$1'")"
    test -z "$SRC_ID" && die "Source account $1 does not exist"
    local DST_ID="$(runsql "select structuredcomm from internal_accounts where structuredcomm like '$2'")"
    test -z "$DST_ID" && die "Destination account $2 does not exist"
    test "$1" == "$2" && die "Source and destination accounts are identical"
    test -z "$3" && die "Specify Point-of-sale ID"
    test -z "$4" && die "Specify amount to transfer from account $SRC_ID to $DST_ID"
    test -z "$5" && die "Specify message for transaction"
    runsql "start transaction;
insert into moneymovements (date_val, date_account, amount, currency, other_account, this_account, message, transaction_id) VALUES 
	    (curdate(), curdate(), abs($4), '$CURRENCY', '$DST_ID', '$SRC_ID', '$5', concat ('INTERNAL/$SRC_ID/$3/', sha1(concat (current_timestamp(), '$5'))) );
insert into moneymovements (date_val, date_account, amount, currency, other_account, this_account, message, transaction_id) VALUES 
	    (curdate(), curdate(), concat ('-', abs ($4)), '$CURRENCY', '$SRC_ID', '$DST_ID', '$5', concat ('INTERNAL/$DST_ID/$3/', sha1(concat (current_timestamp(), '$5'))) );
commit;"
}

# Retrieve amount of money left on the account
# Parameter 1: account ID (belgian structured message)
# output: amount of money left
show_account_balance()
{
    local ACCOUNTID="$(runsql "select structuredcomm from internal_accounts where structuredcomm like '$1'")"
    test -z "$ACCOUNTID" && die "Account $1 does not exist"
    runsql "select abs (sum(amount)) from moneymovements where this_account like '$ACCOUNTID'"
}

# Pre-load some internal accounts into database for future use (cron job)
# Parameter 1: threshold
preload_internal_accounts()
{
    test -z "$1" && die "preload_internal_accounts(): specify amount of messages to pre-load"
    if [ $(runsql 'select count(structuredcomm) from internal_accounts where account_type is null') -lt $1 ]; then #'
	echo 'pre-loading some spare accounts...'
	for i in $(seq 1 $1) ; do
	    runsql 'insert into internal_accounts (structuredcomm) values ( mkbecomm())'
	done
    fi
}

# Create an account for fridge payments
# Parameter 1: member ID
add_bar_account()
{
    local PERSONID="$(lookup_person_id "$1")"
    test -z "$PERSONID" && die "No match found for user '$1'"
    local STRUCTUREDCOMM="$(account_create 'BAR' "$PERSONID" )"
    test -z "$STRUCTUREDCOMM" && die "Account creation failure"
    local MYLANG="$(runsql "select lang from person where id=$PERSONID")"
    local EMAILADDRESS="$(runsql "select emailaddress from person where id=$PERSONID")"
    local FIRSTNAME="$(runsql "select firstname from person where id=$PERSONID")"
    local GPGID="$(runsql "select openpgpkeyid from person where id=$PERSONID")"
    templatecat "$MYLANG" "$ME.sh_person_add_bar.txt" |  do_mail "$MAILFROM" "$EMAILADDRESS" "$GPGID"
}

############################################# </INTERNAL ACCOUNTING> #############################################


# This will create the new payment account for any new user in OU machines, users and internal
cron_mail_new_user()
{
    echo
}

# Set the machine state for specified DN
# PArameter 1: User DN
# Parameter 2: machinestate data
set_machine_state()
{
    echo
}

# Get the machine state for specified DN
# PArameter 1: User DN
# output: machinestate data
get_machine_state()
{
    echo
}


############################################# <MIGRATION> #############################################
# TO DELETE
# Finish the migration and send new password to member
# Parameter 1: Member ID
finish_migration()
{
    local FIRSTNAME="$(runsql "select firstname from person where id=$1")"
    local NICKNAME="$(runsql "select nickname from person where id=$1")"
    local PASSWORD="$(pwgen 20 1)"
    local MYLANG="$(runsql "select lang from person where id=$1")"
    local GPGID="$(runsql "select openpgpkeyid from person where id=$1")"
    local EMAILADDRESS="$(runsql "select emailaddress from person where id=$1")"
    local CRYPTPASSWORD="$(mkpasswd -m sha-512 -s <<< "$PASSWORD")"
    local LDAPHASH="$(/usr/sbin/slappasswd -s "$PASSWORD")"
    if runsql "update person set passwordhash='$CRYPTPASSWORD', ldaphash='$LDAPHASH', machinestate='MEMBERSHIP_ACTIVE' where id=$1" ; then
	echo "Sending new password to $EMAILADDRESS"
	templatecat "$MYLANG" "$ME.sh_person_migrated.txt" |  do_mail "$MAILFROM" "$EMAILADDRESS" "$GPGID"
    fi
}

# Export database to LDIF files
ldapexport()
{
    local UIDBASE=1000
#    for i in $(runsql 'select id from person where ldaphash not like ""'); do
    for i in $(runsql 'select id from person order by id'); do
	local FIRSTNAME="$(runsql "select firstname from person where id=$i")"
	local NAME="$(runsql "select name from person where id=$i")"
	local NICKNAME="$(runsql "select nickname from person where id=$i")"
	local MYLANG="$(runsql "select lang from person where id=$i")"
	local PHONENUMBER="$(runsql "select phonenumber from person where id=$i")" #"
	local EMAILADDRESS="$(runsql "select emailaddress from person where id=$i")"
	local LDAPPASS="$(runsql "select ldaphash from person where id=$i")" #"
	local PASSWDHASH="$(runsql "select concat ('{CRYPT}', passwordhash) from person where id=$i")" #"
	local DESCRIPTION="$(runsql "select machinestate_data from person where id=$i" | tr [:punct:][:cntrl:] ' ' )" #"
	local USER_UID=$(( $UIDBASE + $i ))
	test -z "$LDAPPASS" && LDAPPASS="$PASSWDHASH" # junk password for that user
	echo "dn: uid=$NICKNAME,ou=users,$BASEDN"
	echo "cn:$FIRSTNAME $NAME"
	echo "gidnumber: 503"
	echo "givenname: $FIRSTNAME"
	echo "homedirectory: /home/users/$NICKNAME"
	test -n "$PHONENUMBER" && echo "homephone: $PHONENUMBER"
	echo "mail: $EMAILADDRESS"
	echo "objectclass: inetOrgPerson"
	echo "objectclass: posixAccount"
	echo "objectclass: top"
	echo "objectclass: x-hsbxl-person"
	echo "sn: $NAME"
	echo "uid: $NICKNAME"
	echo "userpassword: $LDAPPASS"
	echo "uidnumber: $USER_UID"
	test -n "$DESCRIPTION" && echo "description: $DESCRIPTION"
	echo ""
    done
}

###################################### Interactive functions ######################################

CMD_adduser()
{
    test "$1" == 'helptext' && echo "add user"
}

CMD_deluser()
{
    test "$1" == 'helptext' && echo "delete user"
}

CMD_dumpargs()
{
    test "$1" == 'helptext' && echo "Dumps arguments" || echo "Arguments: '$1' '$2' '$3'"
}

CMD_runsql()
{
    case "$1" in
    '') echo "Specify SQL request" 
    ;;
    'helptext') echo "Run an SQL command" 
    ;;
    *) runsql "$1" p
    ;;
    esac
}

############################################# </MIGRATION> #############################################

############################################# <INSTALLER> #############################################

# Install LDAP schemas
ldap_install()
{
    echo "$ME: Performing LDAP schema installation..."
    for i in $LDAPSCHEMADIR/*.ldif* ; do
	echo "  -- Processing $i..."
	test "${i: -5}" == ".ldif" && cat "$i" | ldapadd -Y EXTERNAL -H ldapi:///
	test "${i: -14}" == ".ldif.template" && cat "$i" | envsubst | ldapadd -Y EXTERNAL -H ldapi:///
    done
}

############################################# </INSTALLER> #############################################

############################################# <CRON> #############################################
# Refresh PGP key store
cron_pgp()
{
    for i in $(runsql "select openpgpkeyid from person where openpgpkeyid is not null or openpgpkeyid <> ''"); do
	echo "TODO: $i"
    done
}


############################################# </CRON> #############################################

############### </FUNCTIONS> ###############

############### <SANITY CHECKS> ###############
# Load config file and check sanity
test -f "$CONFIGFILE" || die "No config file found ($CONFIGFILE)"
. $CONFIGFILE
test -n "$BANKACCOUNT" || die "$CONFIGFILE: BANKACCOUNT variable is empty"
test -n "$BANKNAME" || die "$CONFIGFILE: BANKNAME variable is empty"
test -n "$MAILFROM" || die "$CONFIGFILE: MAILFROM variable (sender e-mail address) is empty"
test -n "$MONTHLYFEE" || die "$CONFIGFILE: MONTHLYFEE variable is empty"
test -n "$SQLUSER" || die "$CONFIGFILE: SQLUSER variable is empty"
test -n "$SQLPASS" || die "$CONFIGFILE: SQLPASS variable is empty"
test -n "$SQLDB" || die "$CONFIGFILE: SQLDB: Database to use not specified"
test -n "$ORGNAME" || die "$CONFIGFILE: ORGNAME: Organisation name is not set"
test -n "$BASEDN" || die "$CONFIGFILE: BASEDN for LDAP server is not set"
test -n "$DBTYPE" || die "$CONFIGFILE: DBTYPE: Database type is not defined"
# By default we talk in euros
test -n "$CURRENCY" || CURRENCY="EUR"
# A year is (usually) 12 months. This is an override if needed
test -n "$YEARLYFEE" || YEARLYFEE="$((12*$MONTHLYFEE))"
# Default language: english
test -n "$DEFAULT_LANGUAGE" || DEFAULT_LANGUAGE='en'
# In case the bank account number has spaces
BANKACCOUNT=$(echo $BANKACCOUNT|tr -d ' ')
# Minimum Amount of spare accounts to keep aside
test -n "$ACCOUNT_PRELOAD" || ACCOUNT_PRELOAD=10
# If empty, use localhost
test -n "$SQLHOST" || SQLHOST="127.0.0.1"
mkdir -p "$BANKDIR" || die "Can't create csv archive directory"
test -d "$SQLDIR" || die "SQL files repository not found. Current path: $SQLDIR"
mkdir -p "$GPGHOME" || die 'Cannot create GnuPG directory'
chmod 700 "$GPGHOME"

# Check availability of required external software
check_prerequisites mysql bsd-mailx ldapsearch sed awk tr

CASEVAR="$1/$2"

# Nested case statement is shit and unreadable: to delete
case "$1" in
    'member')
	shift
	case "$1" in
	    'cancel')
		test -z "$2" && die 'Spefify person e-mail address'
		membercancel "$2"
		;;
	    'reactivate')
		test -z "$2" && die 'Spefify person e-mail address'
		member_reactivate "$2"
		;;
	    'list_active')
		echo "listing active members..."
		runsql "select id, entrydate, firstname, name, nickname, phonenumber, emailaddress,machinestate from person where machinestate not like 'IMPORTED_EX_MEMBER'"
		;;
	    'list_inactive')
		echo "Listing inactive or ex-members..."
		runsql "select id, entrydate, firstname, name, nickname, phonenumber, emailaddress,machinestate_data from person where machinestate like 'IMPORTED_EX_MEMBER'"
		;;
	    'fix_multiple_payment_msg')
		PERSONID="$(lookup_person_id "$2")"
		test -z "$2" && die 'Spefify person e-mail address'
		test -z "$3" && die 'Spefify the recurring bad message'
		fix_multiple_payment_msg "$2" "$3"
		;;
	    'massmail')
		massmail "$2" "$3"
		;;
	esac
	;;
    "bank")
	shift
	case "$1" in
	    'showflow')
		test -z "$2" && die 'Specify year for the statistics'
		die 'TODO'
		;;
	    'fix_one_msg')
		shift
		test -z "$1" && die 'Specify faulty transaction ID'
		test -z "$2" && die 'Specify correct message'
		runsql "update moneymovements set fix_fuckup_msg='$2' where transaction_id like '$1'"
		;;
	esac
	;;
    "legacy")
	shift
	case "$1" in
	    'activate_all') # To delete
		printf 'Activating %s accounts...\n' "$(runsql 'select count(id) from person where machinestate like "IMPORTED_MEMBER_INACTIVE"')"
		for i in $(runsql 'select id from person where machinestate like "IMPORTED_MEMBER_INACTIVE"') ; do
		    runsql "select id, firstname, name, emailaddress from person where id=$i"
		    finish_migration $i
		done
		;;
	    'activate_one') # to delete
		    test -z "$2" && echo "Awaiting activation:"
		    test -z "$2" && runsql 'select id, nickname, emailaddress from person where machinestate like "IMPORTED_MEMBER_INACTIVE"'
		    test -z "$2" && die "Specify e-mail address to activate"
		    PERSONID="$(lookup_person_id "$2")"
		    finish_migration $PERSONID
		;;
	esac
	;;
esac

# Flattened case statement for easier argument processing.
case "$CASEVAR" in
    "install/" | "install/force")
	shift
	TABLECOUNT="$(runsql "show tables;" 'a')"
	test "$?" = '0' || die "Please create database first"
	test "$1" = 'force' && unset TABLECOUNT
	if [ -z "$TABLECOUNT" ]; then
	    echo "$ME: Priming database..."
	    runsql "$SQLDIR/tables.sql"
	    runsql "$SQLDIR/tabledata.sql"
	    runsql "$SQLDIR/functions.sql"
	    runsql "$SQLDIR/procedures.sql"
	    runsql "$SQLDIR/triggers.sql"
	else
	    die "Database already populated. Use 'force' to override"
	fi
	;;
    "install/ldap")
	ldap_install
	;;

### Person processing
    'person/add')
	addperson 
	;;
    'person/modify')
	PERSONID="$(lookup_person_id "$3")"
	modifyperson "$3" "$4" "$5"
	;;
    'person/changepass')
	PERSONID="$(lookup_person_id "$3")"
	changepassword "$3"
	;;
    'person/resendinfos')
	PERSONID="$(lookup_person_id "$3")"
	resendinfos "$3"
	;;
    'person/addbar')
	add_bar_account "$3"
	;;
    'person/list')
	runsql 'select entrydate,firstname,name,nickname,emailaddress,machinestate from person'
	;;

### Group processing
	'group/list')
	echo "$ME: Available groups:"
	runsql 'select * from hsb_groups order by bit_id'
	;;
	'group/add')
	echo
	;;

### Cron processing
    "cron/hourly")
	cron_mail_new_user
	preload_internal_accounts $ACCOUNT_PRELOAD
	;;
    "cron/daily")
	shift
	cron_pgp
	;;

### Bank processing
    'bank/balance')
	echo "Account			balance		date last movement"
	runsql 'select this_account, sum(amount), max(date_val) from moneymovements group by this_account'
	;;
    'bank/importcsv')
	importbankcsv "$2" "$3"
	;;
    'bank/attributes') # TODO: find a better name
	echo "Updating attributes..."
	bank_fix_membership
	;;

### Member processing
    'member/listpayments')
	test -z "$2" && die 'Spefify person e-mail address or "all" for everyone'
	case "$2" in
	    'all')
		PERSON_ID=$(runsql 'select id from person')
		;;
	    *)
		PERSON_ID="$(lookup_person_id "$2")"
		;;
	esac
	for P in $PERSON_ID ; do 
	    list_person_payments "$P" "$3" 
	done
	;;

### Person processing
    'person/ldapexport')
	ldapexport
	;;

### database backups
    'backup/run')
	db_dump "$3"
	;;
    'backup/restore')
	db_restore "$3"
	;;

### Internal accounting
    'accounting/create')
	account_create "$3" "$4" "$5" "$6"
	;;
    'accounting/preload')
	preload_account "$3" "$4" "$5" "$6"
	;;
    'accounting/consume')
	consume_account "$3" "$4" "$5" "$6"
	;;
    'accounting/transfer')
	transfer_account "$3" "$4" "$5" "$6" "$7"
	;;
    'accounting/balance')
	show_account_balance "$3"
	;;
    'login/')
	# As the current design is as close as running as root (application username/password in config file has full access to databases), 
	# this is a new design that will allow separate administrators accounts. 
	# This is the start of the move away from the single-user database design, and will allow better role segregation and delegation.
	# From now on, LDAP is a hard requirement.
	test -z "$UserName" && read -p 'LDAP Username: ' UserName
	test -z "$UserName" && die 'You must specify user name'
	test -z "$PassWord" && read -s -p 'LDAP Password: ' PassWord
	test -z "$PassWord" && die 'Password cannot be empty'
	echo 
	ldapsearch -o ldif-wrap=no -LLL -h "$LDAPHOST" -D "uid=$UserName,$USERSDN" -w "$PassWord" -b "$BASEDN" > /dev/null || die 'Cannot connect to LDAP server (see above error)'
	while read -p "$UserName@$ME> " COMMAND ARGUMENTS; do
	    case "$COMMAND" in # The different commands
		'exit'|'quit') break
		;;
		'whoami') echo "ldapsearch: $? '$UserName' : '$PassWo'"
		;;
		'?'|'help')
		    printf "List of available commands:\n"
		    printf ' %s	- %s\n' 'help' 'this text'
		    printf ' %s	- %s\n' 'exit' 'Quit this shell'
		    for i in $(declare -F | cut -d ' ' -f 3 | grep 'CMD_'); do
			printf ' %s	- %s\n' "$(sed -e 's/^CMD_//' <<< "$i" )" "$($i helptext)"
		    done
		;;
		'') echo
		;;
		*) test -z "$(declare -F | cut -d ' ' -f 3 | grep "CMD_$COMMAND")" && echo "Unknown command: $COMMAND"
		   test -n "$(declare -F | cut -d ' ' -f 3 | grep "CMD_$COMMAND")" && CMD_$COMMAND "$ARGUMENTS"
		;;
	    esac
	done
	printf "\nGoodbye %s\n" "$UserName"
	;;

### Function debugging
    'debugfunc/')
	declare -F | cut -d ' ' -f 3 | grep 'db'
	askquestions LDAP_FIELDS LDAP_REPLY
	for i in ${!LDAP_REPLY[@]} ; do
	    echo "LDAP_REPLY[$i]=${LDAP_REPLY[$i]}"
#	    echo "$i"
#	    echo "${!LDAP_FIELDS[@]}"
	done
	;;

### Catch-all parts: in case of invalid arguments
    'cron/'*)
	die "Please specify subaction (install|uninstall|yearly|monthly|weekly|daily|hourly|all)"
	;;
    'person/'*)
	die "Please specify subaction (add|modify|changepass|resendinfos|...)"
	;;
    'bank/'*)
	die "Please specify subaction (importcsv|balance||attributes|...)"
	;;
    'legacy/'*)
	die "Please specify subaction (import|activate_all|activate_one|...)"
	;;
    'group/'*)
	die "Please specify subaction (add|listgroups|del|...)"
	;;
    'member/'*)
	die "Please specify subaction (cancel|reactivate|listpayments|list_active|list_inactive|fix_multiple_payment_msg|massmail|...)"
	;;
    'backup/'*)
	die "Please specify subaction (run|restore)"
	;;
    'accounting/'*)
	die "Please specify subaction (create|preload|consume|transfer|balance|sync)"
	;;

### Debugging aid: runsql from command line
    'runsql/'*)
	shift
	test -z "$1" && die 'Specify SQL query to run'
	runsql "$1" "$2"
	;;

# when everything else fails...
    *)
	die "Specify the main action (person|group|bank|member|cron|install|...)"
	;;
esac
