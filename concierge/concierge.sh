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
# Default path to mail templates
readonly TEMPLATEDIR="$MYDIR/templates"
readonly GPGHOME="$MYDIR/.gnupg"
#readonly DEBUGGING=true

############### <FUNCTIONS> ###############
# Function to call when we bail out
die()
{
    echo "$ME: $1. Exit" >&2
    test -n "$2" && exit $2
    exit 1
}

# run a SQL command.
# Parameter 1: SQL request. If it's a valid file, run it's content
# Parameter 2: if set, do not bail out on error
# output: tab-separated data
# exit code 0: request successful
runsql()
{
    test -z "$1" && die "Empty SQL request"
    local SQPROG='echo'
    test -f "$1" && SQPROG='cat'
    if [ -z "$2" ]; then $SQPROG "$1" | mysql -h"$SQLHOST" -u"$SQLUSER" -p"$SQLPASS" -D"$SQLDB" -s --skip-column-names  || die "Failed query: '$1'" # Fix your junk !
		    else $SQPROG "$1" | mysql -h"$SQLHOST" -u"$SQLUSER" -p"$SQLPASS" -D"$SQLDB" -s --skip-column-names  2>&1 # We want the error
    fi
}

# Send the data on STDIN by e-mail.
# Parameter 1: sender address
# Parameter 2: receiver address
# Parameter 3: optional GnuPG key ID. If the key is usable, the mail will be encrypted before sending
# First line will be pasted as subject line
do_mail()
{
    test -z "$1" && die 'No sender address specified'
    test -z "$2" && die 'No receiver address specified'
    local SUBJECTLINE
    # This will eat the first line of stdin
    read SUBJECTLINE
    if [ -z "$DEBUGGING" ] ; then 
	if gpg --no-permission-warning --homedir "$GPGHOME" --fingerprint "$3" > /dev/null 2>&1; then # Is key usable ?
	    gpg --no-permission-warning --homedir "$GPGHOME" --encrypt --armor --batch --always-trust --recipient "$3" | mail -a "From: $1" -s "$ORGNAME - $SUBJECTLINE" "$2"
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
    export STRUCTUREDCOMM BANKACCOUNT CURRENCY YEARLYFEE MONTHLYFEE ORGNAME JOINREASON PASSWORD BIRTHDATE FIRSTNAME NICKNAME EXPIRYDATE LEAVEREASON QUORUM
    cat "$mytemplate" | envsubst
    test -f "$myfooter" && cat "$myfooter" | envsubst
}

addperson()
{
    local REQUESTED_FIELDS=(lang firstname name nickname phonenumber emailaddress birthdate openpgpkeyid machinestate_data)
    local REQUESTED_FIELDS_DESC=('Preferred language' 'Firstname' 'Family name' 'Nickname' 'phone number' 'Email address' 'Birth date' 
				'OpenPGP key ID' "informations (free text, use '|' to finish)\n")
    local -a REPLY_FIELD
    local SQL_QUERY="insert into person ($(tr ' ' ',' <<< "${REQUESTED_FIELDS[@]}"), passwordhash, ldaphash, machinestate, machinestate_expiration_date) values ("
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
    runsql "$SQL_QUERY" && echo "$ME: Added $persontype to database."
    runsql "insert into member_groups (member_id, group_id) values ( (select max(id) from person),(select bit_id from hsb_groups where shortdesc like '$persontype') )" && echo "$ME: Added to group $persontype"
    # If we're here, we have successfully inserted person data
    STRUCTUREDCOMM="$(runsql 'select structuredcomm from person order by id desc limit 1')"
    EXPIRYDATE="$(runsql 'select machinestate_expiration_date from person order by id desc limit 1')"
    FIRSTNAME="${REPLY_FIELD[1]}"
    NICKNAME="${REPLY_FIELD[3]}"
    JOINREASON="${REPLY_FIELD[8]}"
    templatecat "${REPLY_FIELD[0]}" "${ME}.sh_person_add_${persontype}.txt" | do_mail "$MAILFROM" "${REPLY_FIELD[5]}" "${REPLY_FIELD[7]}"
}

# Modify data for an existing user
# Parameter 1: user to modify (e-mail address or nickname)
# Parameter 2: name of field to modify
# Parameter 3: field data
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
    local STRUCTUREDCOMM="$(runsql "select structuredcomm from person where id=$PERSONID")"
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
    local STRUCTUREDCOMM="$(runsql "select structuredcomm from person where id=$PERSONID")"
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
    local STRUCTUREDCOMM="$(runsql "select structuredcomm from person where id=$PERSONID")"
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

# Refresh PGP key store
cron_pgp()
{
    for i in $(runsql "select openpgpkeyid from person where openpgpkeyid is not null or openpgpkeyid <> ''"); do
	echo "TODO: $i"
    done
}

# Columns never used in old app: mail_flags, activateddate, openpgpkeyid, snailbox, snailnumber, snailstreet, snailpostcode, snailcommune, 
#			nationalregistry, birthcountry, birthdate, flags, passwordhash
legacy_import_ex_members()
{
    echo "$ME: Importing ex-members..."
    local record_count=0
    for i in $(runsql "select id from hsbmembers where exitdate is not null"); do
	(( record_count += 1 ))
	local memberdata=($(runsql "select entrydate, exitdate, structuredcomm from hsbmembers where id=$i"))
	local m_firstname="$(runsql "select firstname from hsbmembers where id=$i")"
	local m_name="$(runsql "select name from hsbmembers where id=$i")"
	local m_nickname="$(runsql "select nickname from hsbmembers where id=$i")"
	local m_phone="$(runsql "select phonenumber from hsbmembers where id=$i")"
	local m_email="$(runsql "select emailaddress from hsbmembers where id=$i")"
	local m_why="$(runsql "select why_member from hsbmembers where id=$i" | sed -e "s/[\\']/\\\\&/g")"
	test "$m_nickname" = 'NULL' && m_nickname=''
	test "$m_phone" != 'NULL' && m_phone="'$m_phone'"
	test -z "$m_nickname" && m_nickname="$( tr ' ' '_' <<< "${m_firstname}_${m_name}")" # Craft unlikely nickname
	local PASSWORD="$(pwgen 20 1)"

    local CRYPTPASSWORD="$(mkpasswd -m sha-512 -s <<< "$PASSWORD")"
    local LDAPHASH="$(/usr/sbin/slappasswd -s "$PASSWORD")"

	local SQL_QUERY="insert into person (entrydate, firstname, name, nickname, phonenumber, emailaddress, passwordhash, ldaphash, machinestate, machinestate_data) values 
	    ('${memberdata[0]}', '$m_firstname', '$m_name', '$m_nickname', $m_phone, '$m_email', '$CRYPTPASSWORD', '$LDAPHASH', 'IMPORTED_EX_MEMBER', 'exitdate=\"${memberdata[1]}\";why_member=\"$m_why\"')"
	runsql "$SQL_QUERY"
	# Insert successful ? Prime the old_comms table
	local personid="$(runsql "select id from person where nickname like '$m_nickname'")"
	local oldmsg_query="insert into old_comms (member_id, structuredcomm) values ($personid, '${memberdata[2]}')"
	runsql "$oldmsg_query"
	# delete imported data from old table
	runsql "delete from hsbmembers where id=$i"
#	echo "$i, $personid: $SQL_QUERY - $oldmsg_query"
    done
    echo "$ME: $record_count ex-members records processed"
}

# Columns never used in old app: mail_flags, activateddate, openpgpkeyid, snailbox, snailnumber, snailstreet, snailpostcode, snailcommune, 
#			nationalregistry, birthcountry, birthdate, flags, passwordhash
legacy_import_members()
{
    echo "$ME: Importing members (and keeping them in a silent state)..."
    local record_count=0
    for i in $(runsql "select id from hsbmembers where exitdate is null"); do
#    for i in $(runsql "select id from hsbmembers where exitdate is null and id <> 69 and id <> 101"); do
	(( record_count += 1 ))
	local memberdata=($(runsql "select entrydate, exitdate, structuredcomm from hsbmembers where id=$i"))
	local m_firstname="$(runsql "select firstname from hsbmembers where id=$i")"
	local m_name="$(runsql "select name from hsbmembers where id=$i")"
	local m_nickname="$(runsql "select nickname from hsbmembers where id=$i")"
	local m_phone="$(runsql "select phonenumber from hsbmembers where id=$i")"
	local m_email="$(runsql "select emailaddress from hsbmembers where id=$i")"
	local m_why="$(runsql "select why_member from hsbmembers where id=$i" | sed -e "s/[\\']/\\\\&/g")"
	test "$m_nickname" = 'NULL' && m_nickname=''
	test "$m_phone" != 'NULL' && m_phone="'$m_phone'"
	local PASSWORD="$(pwgen 20 1)"

    local CRYPTPASSWORD="$(mkpasswd -m sha-512 -s <<< "$PASSWORD")"
    local LDAPHASH="$(/usr/sbin/slappasswd -s "$PASSWORD")"

	test -z "$m_nickname" && m_nickname="$( tr ' ' '_' <<< "${m_firstname}_${m_name}")" # Craft unlikely nickname
	if [ -n "$(runsql "select nickname from person where nickname like '$m_nickname'")" ]; then # Do i already have an old inactive entry ?
	    echo "$m_nickname already has a record. Updating it..."
	    local SQL_QUERY="update person set firstname='$m_firstname', name='$m_name', phonenumber=$m_phone, emailaddress='$m_email', 
	    passwordhash='$CRYPTPASSWORD', ldaphash='$LDAPHASH', machinestate='IMPORTED_MEMBER_INACTIVE', machinestate_data='why_member=\"$m_why\"' 
	    where nickname like '$m_nickname'"
	else
	    echo "Importing $m_nickname..."
	    local SQL_QUERY="insert into person (entrydate, firstname, name, nickname, phonenumber, emailaddress, passwordhash, ldaphash, machinestate, machinestate_data) values 
	    ('${memberdata[0]}', '$m_firstname', '$m_name', '$m_nickname', $m_phone, '$m_email', '$CRYPTPASSWORD', '$LDAPHASH','IMPORTED_MEMBER_INACTIVE', 'why_member=\"$m_why\"')"
	fi
#	echo  "$SQL_QUERY"
	runsql "$SQL_QUERY"
	# Insert successful ? Prime the old_comms table
	local personid="$(runsql "select id from person where nickname like '$m_nickname'")"
	local oldmsg_query="insert into old_comms (member_id, structuredcomm) values ($personid, '${memberdata[2]}')"
	runsql "$oldmsg_query"
#	# delete imported data from old table
	runsql "delete from hsbmembers where id=$i"
#	echo "$i, $personid: $SQL_QUERY - $oldmsg_query"
    done
    echo "$ME: $record_count members records processed"
}

# This function will:
# - attribute message strings generated by the old script to the new ones
# - Fix the paying members that insist on not using the communication string
bank_fix_membership()
{
    for i in $(runsql "select id from person") ; do
	local THIS_COMM="$(runsql "select structuredcomm from person where id=$i")"
	for j in $(runsql "select structuredcomm from old_comms where member_id=$i") ; do
	    runsql "update moneymovements set fix_fuckup_msg='$THIS_COMM' where message like '$j'"
	done
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
    local STRUCTUREDCOMM="$(runsql "select structuredcomm from person where id=$1")"
    local ENTRYDATE="$(runsql "select entrydate from person where id=$1")"
    if test $(date '+%Y' -d "$ENTRYDATE") -le $THISYEAR ; then # Don't bother if the person was not member at the time
	printf ' -------- %s %s %s %s %s --------\n' "$ENTRYDATE" "$FIRSTNAME" "$NAME" "$MACHINESTATE" "$STRUCTUREDCOMM"
	runsql "select date_val, this_account, amount, currency, message, fix_fuckup_msg from moneymovements where 
	    (message like '$STRUCTUREDCOMM' or fix_fuckup_msg like '$STRUCTUREDCOMM') and date_val between '$THISYEAR-01-01' and '$THISYEAR-12-31' order by date_val"
    fi
}

# Lookup person ID
# Parameter 1: nickname or email address
# Output: valid person ID from database
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
    for i in $(runsql 'select id from person where ldaphash not like ""'); do
	local FIRSTNAME="$(runsql "select firstname from person where id=$i")"
	local NAME="$(runsql "select name from person where id=$i")"
	local NICKNAME="$(runsql "select nickname from person where id=$i")"
	local MYLANG="$(runsql "select lang from person where id=$i")"
	local PHONENUMBER="$(runsql "select phonenumber from person where id=$i")"
	local EMAILADDRESS="$(runsql "select emailaddress from person where id=$i")"
	local LDAPPASS="$(runsql "select ldaphash from person where id=$i")"
	local USER_UID=$(( $UIDBASE + $i ))
	echo "dn: uid==$NICKNAME,ou=users,dc=hsbxl,dc=be"
	echo "cn:$FIRSTNAME $NAME"
	echo "gidnumber: 503"
	echo "givenname: $FIRSTNAME"
	echo "homedirectory: /home/users/$NICKNAME"
	echo "homephone: $PHONENUMBER"
	echo "mail: $EMAILADDRESS"
	echo "objectclass: inetOrgPerson"
	echo "objectclass: posixAccount"
	echo "objectclass: top"
	echo "sn: $NAME"
	echo "uid: $NICKNAME"
	echo "userpassword: $LDAPPASS"
	echo "uidnumber: $USER_UID"
	echo ""
    done
}

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
# By default we talk in euros
test -n "$CURRENCY" || CURRENCY="EUR"
# A year is (usually) 12 months. This is an override if needed
test -n "$YEARLYFEE" || YEARLYFEE="$((12*$MONTHLYFEE))"
# Default language: english
test -n "$DEFAULT_LANGUAGE" || DEFAULT_LANGUAGE='en'
# In case the bank account number has spaces
BANKACCOUNT=$(echo $BANKACCOUNT|tr -d ' ')
# If empty, use localhost
test -n "$SQLHOST" || SQLHOST="127.0.0.1"
mkdir -p "$BANKDIR" || die "Can't create csv archive directory"
test -d "$SQLDIR" || die "SQL files repository not found. Current path: $SQLDIR"
mkdir -p "$GPGHOME" || die 'Cannot create GnuPG directory'
chmod 700 "$GPGHOME"

case "$1" in
    "install")
	shift
	TABLECOUNT="$(runsql "show tables;" 'a')"
	test "$?" = '0' || die "Please create database first"
	test "$1" = 'force' && unset TABLECOUNT
	if [ -z "$TABLECOUNT" ]; then
	    echo "$ME: Priming database..."
	    runsql "$SQLDIR/tables.sql"
	    runsql "$SQLDIR/tabledata.sql"
# Obsolete table: should be removed
#	    runsql "$SQLDIR/ibandata.sql"
	    runsql "$SQLDIR/functions.sql"
	    runsql "$SQLDIR/procedures.sql"
	    runsql "$SQLDIR/triggers.sql"
	else
	    die "Database already populated. Use 'force' to override"
	fi
	;;
    "person")
	shift
	case "$1" in
	    'add')
		addperson 
		;;
	    'modify')
		PERSONID="$(lookup_person_id "$2")"
		modifyperson "$2" "$3" "$4"
		;;
	    'changepass')
		PERSONID="$(lookup_person_id "$2")"
		changepassword "$2"
		;;
	    'resendinfos')
		PERSONID="$(lookup_person_id "$2")"
		resendinfos "$2"
		;;
	    'list')
		runsql 'select entrydate,firstname,name,nickname,emailaddress,machinestate from person'
		;;
	    'ldapexport')
		ldapexport
		;;
	    *)
		die "Please specify subaction (add|modify|changepass|resendinfos|...)"
		;;
	esac
	;;
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
	    'listpayments')
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
	    *)
		die "Please specify subaction (cancel|reactivate|listpayments|list_active|list_inactive|fix_multiple_payment_msg|massmail|...)"
		;;
	esac
	;;
    'group')
	shift
	case "$1" in
	    'add')
		echo
		;;
	    'listgroups')
		echo "$ME: Available groups:"
		runsql 'select * from hsb_groups order by bit_id'
		;;
	    *)
		die "Please specify subaction (add|listgroups|del|...)"
		;;
	esac
	;;
    "bank")
	shift
	case "$1" in
	    'importcsv')
		importbankcsv "$2" "$3"
		;;
	    'balance')
		echo "Account			balance		date last movement"
		runsql 'select this_account, sum(amount), max(date_val) from moneymovements group by this_account'
		;;
	    'showflow')
		shift
		test -z "$1" && die 'Specify year for the statistics'
		die 'TODO'
		;;
	    'fix_one_msg')
		shift
		test -z "$1" && die 'Specify faulty transaction ID'
		test -z "$2" && die 'Specify correct message'
		runsql "update moneymovements set fix_fuckup_msg='$2' where transaction_id like '$1'"
		;;
	    'attributes') # TODO: find a better name
		echo "Updating attributes..."
		bank_fix_membership
		;;
	    *)
		die "Please specify subaction (importcsv|balance||attributes|...)"
		;;
	esac
	;;
    "cron")
	shift
	cron_pgp
	;;
    "legacy")
	shift
	case "$1" in
	    'import')
		legacy_import_ex_members
		echo "Importing current members..."
		legacy_import_members
		;;
	    'activate_all')
		printf 'Activating %s accounts...\n' "$(runsql 'select count(id) from person where machinestate like "IMPORTED_MEMBER_INACTIVE"')"
		for i in $(runsql 'select id from person where machinestate like "IMPORTED_MEMBER_INACTIVE"') ; do
		    runsql "select id, firstname, name from person where id=$i"
		    #finish_migration $i
		done
		;;
	    'activate_one')
		    test -z "$2" && echo "Awaiting activation:"
		    test -z "$2" && runsql 'select id, nickname, emailaddress from person where machinestate like "IMPORTED_MEMBER_INACTIVE"'
		    test -z "$2" && die "Specify e-mail address to activate"
		    PERSONID="$(lookup_person_id "$2")"
		    finish_migration $PERSONID
		;;
	    *)
		die "Please specify subaction (import|activate_all|activate_one|...)"
		;;
	esac
	;;
    *)
	echo "Specify the main action (person|group|bank|member|cron|install|..."
	;;
esac
