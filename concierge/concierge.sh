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
readonly DEBUGGING=true

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
	    mail -a "From: $1" -s "$ORGNAME - $SUBJECTLINE" "$2"
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
    export STRUCTUREDCOMM BANKACCOUNT CURRENCY YEARLYFEE MONTHLYFEE ORGNAME JOINREASON PASSWORD BIRTHDATE FIRSTNAME NICKNAME EXPIRYDATE
    cat "$mytemplate" | envsubst
    test -f "$myfooter" && cat "$myfooter" | envsubst
}

addperson()
{
    local REQUESTED_FIELDS=(lang firstname name nickname phonenumber emailaddress birthdate openpgpkeyid machinestate_data)
    local REQUESTED_FIELDS_DESC=('Preferred language' 'Firstname' 'Family name' 'Nickname' 'phone number' 'Email address' 'Birth date' 
				'OpenPGP key ID' "informations (free text, use '|' to finish)\n")
    local -a REPLY_FIELD
    local SQL_QUERY="insert into person ($(tr ' ' ',' <<< "${REQUESTED_FIELDS[@]}"), passwordhash, machinestate, machinestate_expiration_date) values ("
    local OPS3="$PS3"
    local persontype='member'
    PS3="Select person type to add (default: $persontype): "
    select persontype in member cohabitants guest landlord contractor; do
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
    case "$persontype" in
	'member')
	    SQL_QUERY="$SQL_QUERY '$(mkpasswd -m sha-512 -s <<< "$PASSWORD")', 'MEMBER_MANUALLY_ENTERED', date_add(now(), interval 1 month) );"
	    ;;
	'cohabitants')
	    SQL_QUERY="$SQL_QUERY '$(mkpasswd -m sha-512 -s <<< "$PASSWORD")', 'COHABITANT_ENTERED', NULL );"
	    ;;
	'guest')
	    SQL_QUERY="$SQL_QUERY '$(mkpasswd -m sha-512 -s <<< "$PASSWORD")', 'GUEST_ENTERED', NULL );"
	    ;;
	'landlord')
	    SQL_QUERY="$SQL_QUERY '$(mkpasswd -m sha-512 -s <<< "$PASSWORD")', 'LANDLORD_ENTERED', NULL );"
	    ;;
	'contractor')
	    SQL_QUERY="$SQL_QUERY '$(mkpasswd -m sha-512 -s <<< "$PASSWORD")', 'CONTRACTOR_ENTERED', NULL );"
	    ;;
    esac
#    echo "$SQL_QUERY"
    runsql "$SQL_QUERY" && echo "$ME: Added $persontype to database."
    runsql "insert into member_groups (member_id, group_id) values ( (select max(id) from person),(select bit_id from hsb_groups where shortdesc like '$persontype') )" && echo "$ME: Added to group $persontype"
    # If we're here, we have successfully inserted person data
    STRUCTUREDCOMM="$(runsql 'select structuredcomm from person order by id desc limit 1')"
    EXPIRYDATE="$(runsql 'select machinestate_expiration_date from person order by id desc limit 1')"
    FIRSTNAME="${REPLY_FIELD[1]}"
    JOINREASON="${REPLY_FIELD[8]}"
    templatecat "${REPLY_FIELD[0]}" "${ME}.sh_person_add_${persontype}.txt" | do_mail "$MAILFROM" "${REQUESTED_FIELDS[5]}" "${REPLY_FIELD[7]}"
}

# Modify data for an existing user
# Parameter 1: user to modify (e-mail address or nickname)
# Parameter 2: name of field to modify
# Parameter 3: field data
modifyperson()
{
    local SELECTED_FIELD
    test -z "$1" && die "Specify the nickname or e-mail address of the person that need to be modified"
    local PERSONID=$(runsql "select id from person where nickname like '$1' or emailaddress like '$1'")
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
    local PERSONID=$(runsql "select id from person where nickname like '$1' or emailaddress like '$1'")
    local PASSWORD="$(pwgen 20 1)"
    test -z "$PERSONID" && die "No match found for user '$1'"
    local MYLANG="$(runsql "select lang from person where id=$PERSONID")"
    local EMAILADDRESS="$(runsql "select emailaddress from person where id=$PERSONID")"
    local FIRSTNAME="$(runsql "select firstname from person where id=$PERSONID")"
    local GPGID="$(runsql "select openpgpkeyid from person where id=$PERSONID")"
    if runsql "update person set passwordhash='$(mkpasswd -m sha-512 -s <<< "$PASSWORD")' where id=$PERSONID" ; then
	templatecat "$MYLANG" "$ME.sh_person_changepassword.txt" |  do_mail "$MAILFROM" "$EMAILADDRESS" "$GPGID"
    fi
}

# Re-send the payment infos for specified user
# Parameter 1: user to re-send infos for
resendinfos()
{
    test -z "$1" && die "Specify the nickname or e-mail address of the person that need a reminder"
    local PERSONID=$(runsql "select id from person where nickname like '$1' or emailaddress like '$1'")
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
    test -z "$1" && die "Specify the nickname or e-mail address of the person that need a reminder"
    local PERSONID=$(runsql "select id from person where nickname like '$1' or emailaddress like '$1'")
    test -z "$PERSONID" && die "No match found for user '$1'"
    echo TODO
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
	echo $i
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
	local PASSWORD="$(pwgen 20 1)"
	local SQL_QUERY="insert into person (entrydate, firstname, name, nickname, phonenumber, emailaddress, passwordhash, machinestate, machinestate_data) values 
	    ('${memberdata[0]}', '$m_firstname', '$m_name', '$m_nickname', $m_phone, '$m_email', '$(mkpasswd -m sha-512 -s <<< "$PASSWORD")', 'IMPORTED_EX_MEMBER', 'exitdate=\"${memberdata[1]}\";why_member=\"$m_why\"')"
	runsql "$SQL_QUERY"
	# Insert successful ? Prime the old_comms table
	local personid="$(runsql "select id from person where emailaddress like '$m_email'")"
	local oldmsg_query="insert into old_comms (member_id, structuredcomm) values ($personid, '${memberdata[2]}')"
	runsql "$oldmsg_query"
	# delete imported data from old table
	runsql "delete from hsbmembers where id=$i"
#	echo "$i, $personid: $SQL_QUERY - $oldmsg_query"
    done
    echo "$ME: $record_count ex-members records processed"
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
	    runsql "$SQLDIR/ibandata.sql"
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
		modifyperson "$2" "$3" "$4"
		;;
	    'changepass')
		changepassword "$2"
		;;
	    'resendinfos')
		resendinfos "$2"
		;;
	    'list')
		runsql 'select entrydate,firstname,name,nickname,emailaddress,machinestate from person'
		;;
	    'test')
		    echo 'Testing stuff...'
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
		;;
	    'listpayments')
		test -z "$2" && die 'Spefify person e-mail address'
		;;
	    *)
		die "Please specify subaction (cancel|reactivate|listpayments|...)"
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
	    *)
		die "Please specify subaction (importcsv|balance|...)"
		;;
	esac
	;;
    "cron")
	shift
	cron_pgp
	;;
    "legacy")
	shift
	legacy_import_ex_members
	echo "Importing current members..."
	legacy_import_members
	;;
    *)
	echo "Specify the main action (person|group|bank|member|cron|install|..."
	;;
esac
