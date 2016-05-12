#!/bin/bash

# 	Member list handler client for Hackerspace Brussels 
#	(c) 2015 Frederic Pasteleurs <frederic@askarel.be>
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
# The raw bank statements will be stored here
#readonly BANKHISTORY="$(dirname $0)/bank"
# Default path for the SQL files
readonly SQLDIR="$MYDIR/sql/"
# Default path to mail templates
readonly TEMPLATEDIR="$MYDIR/templates"
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
    SQPROG='echo'
    test -f "$1" && SQPROG='cat'
    if [ -z "$2" ]; then $SQPROG "$1" | mysql -h"$SQLHOST" -u"$SQLUSER" -p"$SQLPASS" -D"$SQLDB" -s --skip-column-names  || die "Failed query: '$1'" # Fix your junk !
		    else $SQPROG "$1" | mysql -h"$SQLHOST" -u"$SQLUSER" -p"$SQLPASS" -D"$SQLDB" -s --skip-column-names  2>&1 # We want the error
    fi
}

# Send the data on STDIN by e-mail.
# Parameter 1: sender address
# Parameter 2: receiver address
# First line will be pasted as subject line
do_mail()
{
    test -z "$1" && die 'No sender address specified'
    test -z "$2" && die 'No receiver address specified'
    # This will eat the first line of stdin
    read SUBJECTLINE
    if [ -z "$DEBUGGING" ] ; then 
	mail -a "From: $1" -s "$ORGNAME - $SUBJECTLINE" "$2"
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

help()
{
cat <<EOF
Usage: $ME maincommand subcommand parameters

Main commands and subcommands:
    install
	force
    person
	add
	modify
	changepass
	list
    cron
	install
	remove
	run
    doorcontrol
	addtag
	rmtag
	revokeperson
    massmail
EOF
exit 1
}

addperson()
{
    local REQUESTED_FIELDS=(lang firstname name nickname phonenumber emailaddress birthdate openpgpkeyid machinestate_data)
    local REQUESTED_FIELDS_DESC=('Preferred language' 'Firstname' 'Family name' 'Nickname' 'phone number' 'Email address' 'Birth date' 
				'OpenPGP key ID' "informations (free text, use '|' to finish)\n")
    local -a REPLY_FIELD
    local SQL_QUERY="insert into person ($(tr ' ' ',' <<< "${REQUESTED_FIELDS[@]}"), passwordhash, machinestate, machinestate_expiration_date) values ("
    echo "Adding a new person to the system..."
    PASSWORD="$(pwgen 20 1)"
    for (( i=0; i<${#REQUESTED_FIELDS[@]}; i++ )) do
	printf '[%s/%s] %20s: ' "$(( $i + 1 ))" "${#REQUESTED_FIELDS[@]}" "${REQUESTED_FIELDS_DESC[$i]}"
	test $i -lt  $(( ${#REQUESTED_FIELDS[@]} - 1 )) && read REPLY_FIELD[$i] || read -d '|' REPLY_FIELD[$i]
	REPLY_FIELD[$i]="$(sed -e "s/[\\']/\\\\&/g" <<< "${REPLY_FIELD[$i]}")" # Escape quote (avoids SQL injection)
	SQL_QUERY="$SQL_QUERY '${REPLY_FIELD[$i]}',"
    done
    # TODO: add group bits processing here
    SQL_QUERY="$SQL_QUERY '$(mkpasswd -m sha-512 -s <<< "$PASSWORD")', 'MEMBER_MANUALLY_ENTERED', date_add(now(), interval 1 month) );"
#    echo "$SQL_QUERY"
    runsql "$SQL_QUERY" && echo "$ME: Added to database."
    # If we're here, we have successfully inserted person data
    STRUCTUREDCOMM="$(runsql 'select structuredcomm from person order by id desc limit 1')"
    EXPIRYDATE="$(runsql 'select machinestate_expiration_date from person order by id desc limit 1')"
    FIRSTNAME="${REPLY_FIELD[1]}"
    JOINREASON="${REPLY_FIELD[8]}"
    # This must change according to group bits
    templatecat "${REPLY_FIELD[0]}" "${ME}.sh_person_add.txt" | do_mail "$MAILFROM" "${REQUESTED_FIELDS[5]}"
}

# Send a new password for specified user
# Parameter 1: user to change password for
changepassword()
{
    test -z "$1" && die "Specify the nickname or e-mail address of the person that need a new password"
    local PERSONID=$(runsql "select id from person where nickname like '$1' or emailaddress like '$1'")
    PASSWORD="$(pwgen 20 1)"
    test -z "$PERSONID" && die "No match found for user '$1'"
    local MYLANG="$(runsql "select lang from person where id=$PERSONID")"
    local EMAILADDRESS="$(runsql "select emailaddress from person where id=$PERSONID")"
    FIRSTNAME="$(runsql "select firstname from person where id=$PERSONID")"
    if runsql "update person set passwordhash='$(mkpasswd -m sha-512 -s <<< "$PASSWORD")' where id=$PERSONID" ; then
	templatecat "$MYLANG" "$ME.sh_person_changepassword.txt" |  do_mail "$MAILFROM" "$EMAILADDRESS"
    fi
}

cron()
{
    echo ""
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
#mkdir -p "$BANKHISTORY" || die "Can't create csv archive directory"
test -d "$SQLDIR" || die "SQL files repository not found. Current path: $SQLDIR"

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
		shift
		test -z "$1" && die 'Spefify person e-mail address'
		modify "$@"
		;;
	    'changepass')
		shift
		changepassword "$1"
		;;
	    'test')
		shift
		templatecat "$1" "$2" | do_mail "$MAILFROM" "frederic@askarel.be"
		;;
	    *)
		die "Please specify subaction (add|modify|changepass|...)"
		;;
	esac
	;;
    "cron")
	shift
	cron
	;;
    *)
	help
	;;
esac
