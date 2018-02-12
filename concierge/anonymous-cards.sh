#!/bin/bash

readonly ME="$(basename "$0" .sh)"
readonly MYDIR="$(dirname "$0")"
readonly CONFIGFILE="$ME.conf"

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

############### <SANITY CHECKS> ###############
# Load config file and check sanity
test -f "$CONFIGFILE" || die "No config file found ($CONFIGFILE)"
. $CONFIGFILE
test -n "$SQLUSER" || die "$CONFIGFILE: SQLUSER variable is empty"
test -n "$SQLPASS" || die "$CONFIGFILE: SQLPASS variable is empty"
test -n "$SQLDB" || die "$CONFIGFILE: SQLDB: Database to use not specified"
test -n "$ORGNAME" || die "$CONFIGFILE: ORGNAME: Organisation name is not set"
test -n "$PRINTERDEV" || die "$CONFIGFILE: PRINTERDEV: Printer device node is not set"
# By default we talk in euros
test -n "$CURRENCY" || CURRENCY="EUR"
# If empty, use localhost
test -n "$SQLHOST" || SQLHOST="127.0.0.1"
test -e "$PRINTERDEV" || die "$PRINTERDEV does not exist"

# Main
case "$1" in
    'provision')
	runsql 'call intacc_provision (20)'
    ;;
    'preload')
	test -z "$2" && die "Specify amount to preload on card"
	AMOUNT="$2"
	MESSAGE="$3"
	STRUCTUREDCOMM="$(runsql "call intacc_create ('BAR', '', '') " )" #"
	test $? -ne 0 && die "intacc_create failed"
	runsql "call intacc_preload ('$STRUCTUREDCOMM', $AMOUNT, '$CURRENCY', '$MESSAGE')"
	if [ $? -eq 0 ]; then
	    echo "Printing ticket $STRUCTUREDCOMM with amount $AMOUNT $CURRENCY..."
	    EXPDATE="$(date --date="@$(( $(date '+%s' ) + 31536000 ))" '+%Y-%m-%d')" #"
	    export STRUCTUREDCOMM AMOUNT CURRENCY ORGNAME EXPDATE MESSAGE
	    cat "$MYDIR/$ME.printer" |envsubst > "$PRINTERDEV"
	fi
    ;;
    'continuous')
	while test "$AMOUNT" != "exit"; do
	    read -p "Specify amount of card to create and optional message: " AMOUNT MESSAGE
#	    test -n "$AMOUNT" -a "$AMOUNT" != 'exit' && echo "amount=$AMOUNT, message=$MESSAGE"
	    test -n "$AMOUNT" -a "$AMOUNT" != 'exit' && $0 preload "$AMOUNT" "$MESSAGE"
	done
    ;;
    *)
	echo "Usage: $ME continuous|preload <amount>|provision"
    ;;
esac
