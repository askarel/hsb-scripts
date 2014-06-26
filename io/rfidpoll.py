#!/usr/bin/env python

READER=0

MYAPDU= [ 0xff, 0xca, 0x0, 0x0, 0x0 ]

import time
import hashlib
from smartcard.System import readers
from smartcard.CardType import AnyCardType
from smartcard.CardRequest import CardRequest
from smartcard.CardConnection import CardConnection
from smartcard.util import toHexString

r=readers()
print "Reader list:" , r

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
  cardhash=hashlib.md5(responsestr+' '+atrstring).hexdigest()
  print "ATRstring: '"+atrstring+"', response: "+responsestr+", cardhash="+cardhash
 except:
  print "no card"

