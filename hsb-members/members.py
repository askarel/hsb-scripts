#!/usr/bin/env python3

import io

IBAN_LENGTHS = dict( AL=28, AD=24, AT=20, AZ=28, BH=22, BE=16, BA=20,
                     BR=29, BG=22, CR=21, HR=21, CY=28, CZ=24, DK=18,
                     DO=28, EE=20, FO=18, FI=18, FR=27, GE=22, DE=22,
                     GI=23, GR=27, GL=18, GT=28, HU=28, IS=26, IE=22,
                     IL=23, IT=27, KZ=20, KW=30, LV=21, LB=28, LI=21,
                     LT=20, LU=20, MK=19, MT=31, MR=27, MU=30, MC=27,
                     MD=24, ME=22, NL=18, NO=15, PK=24, PS=29, PL=28,
                     PT=25, RO=24, SM=27, SA=24, RS=22, SK=24, SI=19,
                     ES=24, SE=24, CH=21, TN=24, TR=26, AE=23, GB=22,
                     VG=24 )

def check_iban(iban):
    """Checks whether an IBAN, given as a string, is valid"""
    ival = 0

    # Make sure that the string is ASCII, which allows us to use
    # isalpha. To do this, we encode it to ASCII and throw away the
    # result.
    iban.encode('ascii')

    # Strip out all spaces
    iban = iban.replace(' ','')
    # Check length
    if iban[:2] not in IBAN_LENGTHS:
        return False
    if len(iban) != IBAN_LENGTHS[iban[:2]]:
        return False
    # Move four initial characters to the end
    iban = iban[4:] + iban[:4]

    # Convert to an integer; digits are converted directly while
    # letters generate two digits:
    for ch in iban:
        if ch.isalpha():
            ival = ival * 100 + ord(ch.upper()) - ord('A') + 10
        elif ch.isdigit():
            ival = ival * 10 + ord(ch) - ord('0')
        else:
            raise Exception("Invalid character in IBAN")
        # OPTIONAL: Keep the value short for performance
        ival = ival % 97

    return (ival % 97) == 1

def mkcomm(number):
    """Compute a checksum for a Structured Communication value. Number can
    be either an int or a string"""
    if type(number) is str:
        number = int(number, 10)
    res = "%010d%02d" % (number, ((number+96) % 97) + 1)
    return "+++%s/%s/%s+++" % ( res[0:3],res[3:8],res[8:] )
