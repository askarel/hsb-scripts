#!/usr/bin/env python

DATAFILE='/var/local/rfidpoll.txt'
#DATAFILE='rfidpoll.txt'
AR_HASH=0
AR_STARTTIME=1
AR_ENDTIME=2
AR_FLAGS=3
AR_REVOKED=4
AR_NICK=5
BLACKKNIGHTIO='./blackknightio'
BLACKKNIGHTIO='/bin/echo'
MYAPDU= [ 0xff, 0xca, 0x0, 0x0, 0x0 ]

import time
import hashlib
import csv
import syslog
import string
from subprocess import call
from smartcard.System import readers
from smartcard.CardType import AnyCardType
from smartcard.CardRequest import CardRequest
from smartcard.CardConnection import CardConnection
from smartcard.util import toHexString

#r=readers()
syslog.syslog ("RFID reader handler started")

while True:
 time.sleep (0.05)
 cardtype=AnyCardType()
 cardrequest = CardRequest( timeout=2, cardType=cardtype )
 try:
  cardservice = cardrequest.waitforcard()
  cardservice.connection.connect()
  atrstring=hashlib.md5 ("< OK: "+toHexString( cardservice.connection.getATR())+' \n').hexdigest()
  response, sw1, sw2 = cardservice.connection.transmit (MYAPDU, CardConnection.T1_protocol)
  responsestr=hashlib.md5("< "+toHexString (response)+" %.2x %.2x : Normal processing.\n" % (sw1, sw2)).hexdigest()
  if cardhash=='':
   cardhash=hashlib.md5(responsestr+' '+atrstring).hexdigest() # Got card hash
   try: 
    with open(DATAFILE) as f: 
     csvreader=csv.reader(f, delimiter="\t")
     h=list(csvreader)
     for l in h:
      if l[AR_HASH]==cardhash: # Is the hash in data file ?
       if int(l[AR_STARTTIME]) < int(time.time()): # Is it active yet ?
        if int(l[AR_REVOKED]) == 0: # Is it still active ?
         if l[AR_ENDTIME] == 'NULL': # NULL expiration (valid)
          call([BLACKKNIGHTIO, 'open', 'tag '+ l[AR_HASH]])
         elif l[AR_ENDTIME] == '0': # Zero expiration (valid)
          call([BLACKKNIGHTIO, 'open', 'tag '+ l[AR_HASH]])
         elif int(l[AR_ENDTIME]) > int(time.time()): # Did it expire ?
          call([BLACKKNIGHTIO, 'open', 'tag '+ l[AR_HASH]])
         else:
          syslog.syslog (format ( "Card %s is expired. User: %s" %  (l[AR_HASH], l[AR_NICK])))
        else:
         syslog.syslog (format ("Card %s is deactivated. User: %s, Reason: %x" %  (l[AR_HASH], l[AR_NICK], int(l[AR_REVOKED]))))
       else:
        syslog.syslog (format ( "Card %s not yet active, User %s" %  (l[AR_HASH], l[AR_NICK])))
       break
     else:
      syslog.syslog (format ( "Card not found: %s" % cardhash))
   except:
    syslog.syslog ( "Cannot open file: "+DATAFILE)

#   print "ATRstring: '"+atrstring+"', response: "+responsestr+", cardhash="+cardhash
 except:
#  print "no card"
  cardhash=''

