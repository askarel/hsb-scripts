#! /bin/bash

# 	Argenta CSV parser, formatter and sanitizer
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
#        v Top of file
# CSV[0]=Numéro du compte :;BE69 9794 2977 5578;Giro +
# CSV[1]=Date valeur;Référence de l'opération;Description;Montant de l'opération;Devise;Date d'opération;Compte de contrepartie;Nom de la contrepartie :;Communication 1 :;Communication 2 :
# CSV[2]=01-01-2015;B4L31IN5K00A1B2A;Votre décompte d'intérêts;1,71;EUR;31-12-2014;979-4297755-78; ; ; 
#             1          2               3                      4    5     6             7        8 9 10             

ME=$(basename $0)

declare -a VALIDIBAN=('AL;28' 'AD;24' 'AT;20' 'AZ;28' 'BH;22' 'BE;16' 'BA;20' 'BR;29' 'BG;22' 'CR;21' 'HR;21' 'CY;28' 'CZ;24' 'DK;18' 'DO;28' 'EE;20' 'FO;18' 
			'FI;18' 'FR;27' 'GE;22' 'DE;22' 'GI;23' 'GR;27' 'GL;18' 'GT;28' 'HU;28' 'IS;26' 'IE;22' 'IL;23' 'IT;27' 'KZ;20' 'KW;30' 'LV;21' 'LB;28'
			'LI;21' 'LT;20' 'LU;20' 'MK;19' 'MT;31' 'MR;27' 'MU;30' 'MC;27' 'MD;24' 'ME;22' 'NL;18' 'NO;15' 'PK;24' 'PS;29' 'PL;28' 'PT;25' 'RO;24'
			'SM;27' 'SA;24' 'RS;22' 'SK;24' 'SI;19' 'ES;24' 'SE;24' 'CH;21' 'TN;24' 'TR;26' 'AE;23' 'GB;22' 'VG;24')

# Function to call when we bail out
die()
{
    printf "%s: %s. Exit\n" "$ME" "$1"
    test -z "$2" && exit 1 || exit $2
}

# Verify belgian-style account number. It has 12 digits separated by dashes.
# The two last digits are the modulo 97 of the 10 first. Set to 97 if zero.
# input: what look like a belgian account number
# output: cleanly formatted belgian account number. Nothing if garbage
function verifybe()
{
    # Clean anything that do not look like a digit
    CLEANBE="$(sed -e 's/[^0-9]//gI' <<< "$1")"
    MODULO="${CLEANBE:10:2}"
    ACCOUNTNR="${CLEANBE:0:10}"
    test $MODULO -ne "$(( 10#$ACCOUNTNR % 97 ))" || echo "${CLEANBE:0:3}-${CLEANBE:3:7}-$MODULO"
    test "$MODULO" = '97' -a "$(( 10#$ACCOUNTNR % 97 ))" = '0' && echo "${CLEANBE:0:3}-${CLEANBE:3:7}-$MODULO"
}

# Verify the IBAN account number. 
# Input: what look like an IBAN number
# output: a clean IBAN number with no space. Nothing if garbage.
# Documentation: http://en.wikipedia.org/wiki/International_Bank_Account_Number
function verifyiban()
{
    # Do not remove front space: seq is 1-based, bash strings are zero-based.
    IBANTABLE=" ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    # Remove all spaces and junk from the string. They will be added later when needed.
    IBAN=$(tr [:lower:] [:upper:] <<< "$1" | sed -e 's/[^0-9A-Z]//gI')
    IBANCOUNTRY=${IBAN:0:2}
    IBANMODULO=${IBAN:2:2}
    IBANACCOUNT=${IBAN:4}
    for i in ${VALIDIBAN[@]}; do 
	test "${i:0:2}" = "$IBANCOUNTRY" && IBANLENGTH="${i:3:2}"
    done
    # Is it in IBAN database ? 
    test -z "$IBANLENGTH" && return
    # Is it the correct length ?
    if [ "$IBANLENGTH" -eq "${#IBAN}" ]; then
	# Build sed script to transform letters in numbers (A=10, B=11, C=12, D=13, E=14,... Z=35)
	for (( i=1; i<${#IBANTABLE}; i++ )) do
	    SEDSCRIPT="s/${IBANTABLE:$i:1}/$(( $i + 9 ))/gI;$SEDSCRIPT"
	done
	# Convert letters to digits
	NUMIBAN="$(sed -e "$SEDSCRIPT" <<< "$IBANACCOUNT$IBANCOUNTRY$IBANMODULO")"
	INTMOD="$(( 10#${NUMIBAN:0:9} % 97))"	# First chunk
	for (( i=9; i<= ${#NUMIBAN}; i=i+7 )) do
	    INTMOD="$(( 10#$INTMOD${NUMIBAN:$i:7} % 97 ))" # Process the other chunks
	done
	test "$INTMOD" -eq 1 && echo "$IBAN" # If we're left with just the number 1, the bank account number is valid.
    fi
}

case "$1" in
    'import')
	test -z "$2" && die "No file specified"
	test -f "$2" || die "File '$2' does not exist or not regular file"
	readarray -t CSV < "$2" # Load CSV file into array
	MYACCOUNT="$( verifyiban "$(cut -d ';' -f 2 <<< "${CSV[0]}")")" # To IBANify #"
	test -z "$MYACCOUNT" && die "This does not look like an Argenta bank statement file"
	$0 header
	for (( i=2; i<${#CSV[@]}; i++ )) do
	    date_val="$(cut -d ';' -f 1 <<< "${CSV[$i]}" | awk 'BEGIN {FS="-"; OFS="-"} { print $3,$2,$1 }')"
	    date_account="$(cut -d ';' -f 6 <<< "${CSV[$i]}" | awk 'BEGIN {FS="-"; OFS="-"} { print $3,$2,$1 }')"
	    other_account="$(cut -d ';' -f 7 <<< "${CSV[$i]}")" # To IBANify ?
	    amount="$(cut -d ';' -f 4 <<< "${CSV[$i]}"|sed -e 's/\.//g'|sed -e 's/\,/\./g')"	# Remove thousands separating dot, and convert decimal comma to dot
	    currency="$(cut -d ';' -f 5 <<< "${CSV[$i]}")"	# as-is ?
	    message="$(cut -d ';' -f 9 <<< "${CSV[$i]}")"
	    message2="$(cut -d ';' -f 10 <<< "${CSV[$i]}")"
	    test "$message2" != '' -a "$message2" != ' ' && message="$message$message2" # Append second message only if something is present.
	    other_account_name="$(cut -d ';' -f 8 <<< "${CSV[$i]}")"	# as-is
	    transaction_id="BANK/ARGENTA/$MYACCOUNT/$(cut -d ';' -f 2 <<< "${CSV[$i]}")" # Category/module/bank account/transactionID
	    printf "\"%s\";\"%s\";\"%s\";\"%s\";\"%s\";\"%s\";\"%s\";\"%s\";\"%s\";\"%s\"\n" "$date_val" "$date_account" "$MYACCOUNT" "$other_account" "$amount" "$currency" "$message" "$other_account_name" "$transaction_id" "${CSV[$i]}"
	done
	echo "$ME: $2: ${#CSV[@]} lines, 2 header lines, $(( $i - 2 )) lines processed." > /dev/stderr
	;;
    'header')
	echo "@date_val;@date_account;this_account;other_account;amount;currency;message;other_account_name;transaction_id;raw_csv_line"
	;;
    'testcode')
	verifyiban "$2"
	;;
	*)
	echo "usage: $ME [import|header] filename"
	exit 1
	;;
esac
exit 0

# Old code. For reference only


# Convert belgian style account number to IBAN number
# input: belgian style or IBAN bank account number
# output: IBANized bank account number. Pass through if already IBANized. No output in case of garbage input.
function be2iban()
{
    test -n "$(verifyiban "$1")" && verifyiban "$1"
    if [ -n "$(verifybe "$1")" ]; then
	# Clean anything that do not look like a digit
	CLEANBE="$(echo "$1"|sed -e 's/[^0-9]//gI')"
	if [ $(wc -c <<< "$CLEANBE") -eq '13' ]; then
	    MODULO="$(( ( 10#${CLEANBE}111400 % 97 ) - 98 ))"
	    test "$MODULO" -lt 0 && MODULO="$(( 10#$MODULO * -1 ))"
	    printf 'BE%02d%012d' "$(( 10#$MODULO ))" "$(( 10#$CLEANBE ))"
	fi
    fi
}
