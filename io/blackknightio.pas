program blackknightio;
{
 Make I/O on a shift register (74LS673) coupled to an input multiplexer (74150)
 using a raspberry pi and only 4 GPIO lines

 (c) 2013 Frederic Pasteleurs <frederic@askarel.be>

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 3 of the License, or
 (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program or from the site that you downloaded it
 from; if not, see <http://www.gnu.org/licenses/>.

 The PiGPIO library included in this repository is (c) 2013 Gábor Szöllösi
}

// This is a quick hack to check if everything works

uses PiGpio, sysutils, crt, keyboard, strutils, baseunix, ipc, systemlog, pidfile;

CONST   SHITBITS=63;

TYPE    TDbgArray= ARRAY [0..15] OF string[15];
        TRegisterbits=bitpacked array [0..15] of boolean; // Like a word: a 16 bits bitfield
        TLotsofbits=bitpacked array [0..SHITBITS] of boolean; // A shitload of bits to abuse. 64 bits should be enough. :-)
        TSHMVariables=RECORD // What items should be exposed for IPC.
//                PIDofmain:TPid;
                Inputs, outputs, fakeinputs: TRegisterbits;
                state, Config :TLotsofbits;
                Command: byte;
                SHMMsg:string;
//                lastcommandstatus: byte;
                end;
        TConfigTextArray=ARRAY [0..SHITBITS] of string[20];
{        TLogItem=ARRAY [0..SHITBITS] OF RECORD // Log and debug text, with alternative and levels
                msglevel: byte;
                msg: string;
                altlevel: byte;
                altmsg: string;
                end;
 }
CONST   CLOCKPIN=7;  // 74LS673 pins
        STROBEPIN=8;
        DATAPIN=25;
        READOUTPIN=4; // Output of 74150
        MAXBOUNCES=8;

        // Possible commands and their names
        CMD_NONE=0; CMD_OPEN=1; CMD_TUESDAY=2; CMD_ENABLE=3; CMD_DISABLE=4; CMD_BEEP=5; CMD_STOP=6;
        CMD_NAME: ARRAY [CMD_NONE..CMD_STOP] of pchar=('NoCMD','open','tuesday','enable','disable','beep','stop');

        bits:array [false..true] of char=('0', '1');
        // Hardware bug: i got the address lines reversed while building the board.
        // Using a lookup table to mirror the address bits
        BITMIRROR: array[0..15] of byte=(0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15);
{
        // Log level consts for the logging function
        LOG_DEBUGMODE=false;
        LOG_NONE=0; LOG_DEBUG=1; LOG_EMAIL=2; LOG_CRIT=3; LOG_ERR=4; LOG_WARN=5; LOG_INFO=6;
        LOGPREFIXES: ARRAY [0..LOG_INFO] of string[10]=('', 'DEBUG', 'Mail', 'CRITICAL', 'ERROR', 'Warning', 'Info');

        LOG_MSG_STOP=0; LOG_MSG_START=1; LOG_MSG_BOXTAMPER=2; LOG_MSG_TRIPWIRE=3; LOG_MSG_PANIC=4; LOG_MSG_HALLWAYLIGHT=5; LOG_MSG_MAIL=6;
        LOG_MSG_TUESDAY=7; LOG_MSG_MAG1LOCKED=8; LOG_MSG_MAG2LOCKED=9; LOG_MSG_DOORLEAFSWITCH=10; LOG_MSG_MAGLOCK1ON=11; LOG_MSG_MAGLOCK2ON=12;
        LOG_MSG_STRIKEON=13; LOG_MSG_DOORISLOCKED=14; LOG_MSG_SOFTOPEN=15; LOG_MSG_SWITCHOPEN=16; LOG_MSG_HANDLEOPEN=17; LOG_MSG_HANDLELIGHTOPEN=18;

        LOG_MSG:TLogItem=( (msglevel: LOG_CRIT; msg: 'Application is exiting !!'; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_EMAIL; msg: 'Application is starting...'; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_CRIT; msg: 'TAMPER ALERT: CONTROL BOX IS BEING OPENED !!'; altlevel: LOG_DEBUG; altmsg: 'Control box is closed.'),
                           (msglevel: LOG_CRIT; msg: 'TRIPWIRE LOOP BROKEN: POSSIBLE BREAK-IN !!'; altlevel: LOG_DEBUG; altmsg: 'Tripwire loop ok'),
                           (msglevel: LOG_CRIT; msg: 'PANIC SWITCH PRESSED: MAGLOCKS PHYSICALLY DISCONNECTED'; altlevel: LOG_DEBUG; altmsg: 'Don''t panic'),
                           (msglevel: LOG_INFO; msg: 'Hallway light is on'; altlevel: LOG_INFO; altmsg: 'Hallway light is off'),
                           (msglevel: LOG_EMAIL; msg: 'We have mail in the mailbox.'; altlevel: LOG_INFO; altmsg: 'No mail.'),
                           (msglevel: LOG_EMAIL; msg: 'Tuesday mode: ring doorbell to enter'; altlevel: LOG_EMAIL; altmsg: 'Leaving tuesday mode'),
                           (msglevel: LOG_INFO; msg: 'Door is locked by maglock 1'; altlevel: LOG_ERR; altmsg: 'Maglock 1 shoe NOT detected !!'),
                           (msglevel: LOG_INFO; msg: 'Door is locked by maglock 2'; altlevel: LOG_ERR; altmsg: 'Maglock 2 shoe NOT detected !!'),
                           (msglevel: LOG_INFO; msg: 'Door is open.'; altlevel: LOG_INFO; altmsg: 'Door is closed (does not mean locked).'),
                           (msglevel: LOG_INFO; msg: 'Maglock 1 is on'; altlevel: LOG_INFO; altmsg: 'Maglock 1 is off'),
                           (msglevel: LOG_INFO; msg: 'Maglock 2 is on'; altlevel: LOG_INFO; altmsg: 'Maglock 2 is off'),
                           (msglevel: LOG_INFO; msg: 'Door strike is on'; altlevel: LOG_DEBUG; altmsg: 'Door strike is off'),
                           (msglevel: LOG_INFO; msg: 'Door is locked'; altlevel: LOG_EMAIL; altmsg: 'DOOR IS NOT LOCKED !!'),
                           (msglevel: LOG_EMAIL; msg: 'Door opening request from system'; altlevel: LOG_NONE; altmsg: 'system is quiet'),
                           (msglevel: LOG_EMAIL; msg: 'Door opening request from button'; altlevel: LOG_NONE; altmsg: 'No button touched'),
                           (msglevel: LOG_EMAIL; msg: 'Door opening request from handle'; altlevel: LOG_NONE; altmsg: 'handle not touched'),
                           (msglevel: LOG_INFO; msg: 'Door opening request, light+handle'; altlevel: LOG_NONE; altmsg: 'Light+handle conditions not met'),
                           (msglevel: LOG_CRIT; msg: ''; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''), (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''), (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''), (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''), (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''), (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''), (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''), (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''), (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''), (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''), (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''), (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''), (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''), (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''), (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''), (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''), (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''), (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''), (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_ERR; msg: 'System is disabled in software'; altlevel: LOG_NONE; altmsg: 'System is enabled'),
                           (msglevel: LOG_ERR; msg: 'Check wiring or leaf switch: door is maglocked, but i see it open.'; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_ERR; msg: 'Check wiring or maglock 1: Disabled in config, but i see it locked.'; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_ERR; msg: 'Check wiring or maglock 2: Disabled in config, but i see it locked.'; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: '')
                           );
 }       // Various timers, in milliseconds (won't be accurate at all, but time is not critical)
        COPENWAIT=4000; // How long to leave the door unlocked after receiving open order
        LOCKWAIT=2000; // Maximum delay between leaf switch closure and maglock feedback switch closure (if delay expired, alert that the door is not closed properly
        BUZZERCHIRP=150; // Small beep delay
//        SND_MISTERCASH: ARRAY OF WORD=(200, 200, 200, 200, 200, 200, 0, 0);

        // Available outputs on 74LS673. Outputs Q0 to Q3 are connected to the address inputs of the 74150
        Q15=0; Q14=1; Q13=2; Q12=3; Q11=4; Q10=5; Q9=6; Q8=7; Q7=8; Q6=9; Q5=10; Q4=11;
        // Use more meaningful descriptions of the outputs in the code
        // Outputs Q12, Q13, Q14 and Q15 are not used for the moment. Status LED maybe ?
        BUZZER_OUTPUT=Q4;
        BATTERY_RELAY=Q7;
        MAGLOCK1_RELAY=Q9;
        MAGLOCK2_RELAY=Q8;
        DOOR_STRIKE_RELAY=Q10;
        LIGHT_CONTROL_RELAY=Q6;
        DOORBELL_INHIBIT_RELAY=Q5;
        REDLED=Q14;
        GREENLED=Q15;
        // Available inputs from the 74150
        I15=15; I14=14; I13=13; I12=12; I11=11; I10=10; I9=9; I8=8; I7=7; I6=6; I5=5; I4=4; I3=3; I2=2; I1=1; I0=0;
        // Use more meaningful descriptions of the inputs in the code
        // Inputs OPTO4, IN2 and IN1 are not used for the moment.
        // The numbers below correspond to the numbers printed on the screw terminals
        IN11=I0; IN10=I1; IN9=I2; IN8=I3; IN7=I4; IN6=I5; IN5=I6; IN4=I7; IN3=I8; IN2=I9; IN1=I10; OPTO1=I12; OPTO2=I13; OPTO3=I14; OPTO4=I15;
        PANIC_SENSE=I11;
        DOORBELL1=OPTO1;
        DOORBELL2=OPTO2;
        DOORBELL3=OPTO3;
        BOX_TAMPER_SWITCH=IN11;
        MAGLOCK1_RETURN=IN10;
        MAGLOCK2_RETURN=IN9;
        LIGHTS_ON_SENSE=IN6;
        DOOR_CLOSED_SWITCH=IN5;
        DOORHANDLE=IN4;
        MAILBOX=IN3;     // Of course we'll have physical mail notification. :-)
        TRIPWIRE_LOOP=IN2;
        DOOR_OPEN_BUTTON=IN1;
        IS_CLOSED=false;
        IS_OPEN=true;
        DBGINSTATESTR: Array [IS_CLOSED..IS_OPEN] of string[5]=('closed', 'open');
        DBGOUTSTATESTR: Array [false..true] of string[5]=('On', 'Off');
        CFGSTATESTR: Array [false..true] of string[8]=('Disabled','Enabled');
        DBGOUT: TDbgArray=('Green LED', 'Red LED', 'Q13 not used', 'Q12 not used', 'relay not used', 'strike', 'mag1 power', 'mag2 power', 'not used',
                                'light', 'bell inhib.', 'Buzzer', '74150 A3', '74150 A2', '74150 A1', '74150 A0');
        DBGIN: TDbgArray=('TAMPER BOX','MAG1 CLOSED','MAG2 CLOSED','IN 8','IN 7','Light on sense','door closed','Handle',
                          'Mailbox','Tripwire','opendoorbtn','PANIC SWITCH','DOORBELL 1','DOORBELL 2','DOORBELL 3','OPTO 4');
        // offsets in status/config bitfields
        SC_MAGLOCK1=0; SC_MAGLOCK2=1; SC_TRIPWIRE_LOOP=2; SC_BOX_TAMPER_SWITCH=3; SC_MAILBOX=4; SC_BUZZER=5; SC_BATTERY=6; SC_HALLWAY=7;
        SC_DOORSWITCH=8; SC_HANDLEANDLIGHT=9; SC_DOORUNLOCKBUTTON=10; SC_HANDLE=11; SC_DISABLED=12;
        // Status bit block only
        S_DEMOMODE=63; S_TUESDAY=62; S_STOP=61; S_HUP=60;

        // Static config
        STATIC_CONFIG_STR: TConfigTextArray=('Maglock 1',
                                             'Maglock 2',
                                             'Tripwire loop',
                                             'Box tamper',
                                             'Mail notification',
                                             'buzzer',
                                             'Backup Battery',
                                             'Hallway lights',
                                             'Door leaf switch',
                                             'handle+light unlock',
                                             'Door unlock button',
                                             'Handle unlock only',
                                             'Software-disabled',
                                             '', '',  '', '', '', '', '', '', '', '', '', '', '',
                                             '', '', '', '', '', '', '', '', '',  '', '', '', '', '', '', '', '', '', '',
                                             '', '', '', '', '', '', '', '', '',  '', '', '', '', '', '', 'HUP received', 'Stop order', 'Tuesday mode', 'Demo mode');

        STATIC_CONFIG: TLotsOfBits=(false,  // SC_MAGLOCK1 (Maglock 1 installed)
                                    true, // SC_MAGLOCK2 (Maglock 2 not installed)
                                    false,  // SC_TRIPWIRE_LOOP (Tripwire not installed)
                                    false,  // SC_BOX_TAMPER_SWITCH (Tamper switch installed)
                                    true,  // SC_MAILBOX (Mail detection installed)
                                    true,  // SC_BUZZER (Let it make some noise)
                                    false, // SC_BATTERY (battery not attached)
                                    false, // SC_HALLWAY (Hallway light not connected)
                                    true,  // SC_DOORSWITCH (Door leaf switch installed)
                                    true,  // SC_HANDLEANDLIGHT (The light must be on to unlock with the handle)
                                    true,  // SC_DOORUNLOCKBUTTON (A push button to open the door)
                                    false, // SC_HANDLE (Unlock with the handle only: not recommended in HSBXL)
                                    true, // SC_DISABLED (system is software-disabled)
                                    false,
                                    false, false, false, false, false, false, false, false, false, false, false, false, false,
                                    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
                                    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
                                    false, false,
                                    false, // Unused
                                    false, // Unused
                                    false  // Unused
                                    );

VAR     GPIO_Driver: TIODriver;
        GpF: TIOPort;
        debounceinput_array: ARRAY[false..true, 0..15] of byte; // That one has to be global. No way around it.
        CurrentState,   // Reason for global: it is modified by the signal handler
        msgflags: TLotsOfBits; // Reason for global: message state must be preserved (avoid spamming the syslog)

///////////// COMMON LIBRARY FUNCTIONS /////////////

// Return gray-encoded input
function graycode (inp: longint): longint;
begin
 graycode:=(inp shr 1) xor inp;
end;

function word2bits (inputword: word): TRegisterbits;
begin
 word2bits:=TRegisterbits (inputword); // TRegisterbits is a word-sized array of bits
end;

function bits2word (inputbits: TRegisterbits): word;
begin
 bits2word:=word (inputbits);
end;

function bits2str (inputbits: TRegisterbits): string;
var i: byte;
    s: string;
begin
 s:='';
 for i:=(bitsizeof (TRegisterbits)-1) downto 0 do s:=s+bits[inputbits[i]];
 bits2str:=s;
end;

// TODO: glitch counter
function debounceinput (inputbits: TRegisterbits; samplesize: byte): TRegisterbits;
var i: byte;
begin
 for i:=0 to 15 do
  begin
//  delay (10);
   debounceinput_array[inputbits[i]][i]:= debounceinput_array[inputbits[i]][i] + 1; // increment counters
//   writeln ('input[0] state: ', inputbits[0], '  debounce 0[0]: ', debounceinput_array[false][0], '  debounce 1[0]', debounceinput_array[true][0], '    ');
   if debounceinput_array[false][i] >= samplesize then
    begin
     debounceinput_array[true][i]:=0; // We have a real false, resetting counters
     debounceinput_array[false][i]:=0;
     debounceinput[i]:=false;
    end;
   if debounceinput_array[true][i] >= samplesize then
    begin
     debounceinput_array[true][i]:=0; // we have a real true, resetting counters
     debounceinput_array[false][i]:=0;
     debounceinput[i]:=true;
    end;
  end;
end;

// Apparently, despite the crappy CPU on the raspberry pi, it is too fast for the shift register.
// This should help the shift register to settle
procedure wastecpucycles (waste: word);
var i: word;
begin
 for i:=0 to waste do
  asm
   nop // How handy... This is portable ASM... :-)
  end;
end;

// Decrement the timer variable
procedure busy_delay_tick (var waitvar: longint; ticklength: word);
var mytick: word;
begin
 if ticklength <= 0 then mytick:=1 else mytick:=ticklength;
 if waitvar >= 0 then waitvar:=waitvar - ticklength else waitvar:=0;
end;

// Is the timer expired ?
function busy_delay_is_expired (var waitvar: longint): boolean;
begin
 if waitvar <= 0 then busy_delay_is_expired:=true
                 else busy_delay_is_expired:=false;
end;

// Buzzer functions ?
// Needed functions:  buzzer handling

procedure logexec (msgindex: byte; var flags: TLotsOfBits; msg: string);
begin

end;

{
// Log an event (NEED REWRITE)
procedure log_door_event (msgindex: byte; use_alt_msg: boolean; var flags: TLotsOfBits; doorevent:TLogItem; debugmode: boolean; extratext: string);
var logstring: string;
begin
 logstring:=FormatDateTime ('YYYY-MM-DD HH:MM:SS', now) + ' ';
 if use_alt_msg then
  if flags[msgindex] then // Alternate message
   begin
    flags[msgindex]:=false;
    logstring:=logstring + LOGPREFIXES[doorevent[msgindex].altlevel] +  ': ' + doorevent[msgindex].altmsg;
    if extratext = '' then writeln (logstring)
                      else writeln (logstring, ' (', extratext, ')');
   end
   else
   begin
   end
 else
  if not flags[msgindex] then
   begin
    flags[msgindex]:=true;
    logstring:=logstring + LOGPREFIXES[doorevent[msgindex].msglevel] + ': ' + doorevent[msgindex].msg;
    if extratext = '' then writeln (logstring)
                      else writeln (logstring, ' (', extratext, ')');
   end;
end;
 }
// Reset a log event
procedure log_door_reset (msgindex: byte; use_alt_msg: boolean; var flags: TLotsOfBits);
begin
 if use_alt_msg
  then flags[msgindex]:=true
  else flags[msgindex]:=false;
end;

procedure dump_config (bits: TLotsofbits; textdetail:TConfigTextArray );
var i: byte;
begin
 for i:=0 to SHITBITS do if textdetail[i] <> '' then writeln ('Config option ', i, ': ', textdetail[i], ': ', CFGSTATESTR[bits[i]]);
end;

///////////// DEBUG FUNCTIONS /////////////

// Decompose a word into bitfields with description
procedure debug_showbits (inputbits, oldbits: TRegisterbits; screenshift: byte; description: TDbgArray );
const modchar: array [false..true] of char=(' ', '>');
var i, oldx, oldy: byte;
begin
 if bits2word (inputbits) <> bits2word (oldbits) then
 begin
  oldx:=wherex; oldy:=wherey;
  for i:=0 to 15 do
   begin
    description[i][0]:=char (15);// Trim length
    gotoxy (1 + screenshift, i + 2); write ( bits[inputbits[i]], modchar[(inputbits[i]<>oldbits[i])], description[i]);
   end;
   gotoxy (oldx, oldy);
 end;
//  writeln;
end;

// This run as another process and will monitor the SHM buffer for changes.
// If in demo mode, you will be able to fiddle the inputs
procedure run_test_mode (daemonpid: TPid);
var  shmid: longint;
     shmkey: TKey;
     SHMPointer: ^TSHMVariables;
     oldin, oldout: TRegisterbits;
     shmname, key: string;
     K: TKeyEvent;
     quitcmd: boolean;
     i: byte;
begin
 if daemonpid = 0 then
  begin
   writeln ('Daemon not started.');
   halt (1);
  end
 else
  begin
   shmname:=paramstr (0) + #0;
   shmkey:=ftok (pchar (@shmname[1]), daemonpid);
   shmid:=shmget (shmkey, sizeof (TSHMVariables), 0);
   // Add test for shmget error here ?
   SHMPointer:=shmat (shmid, nil, 0);

   oldin:=word2bits (0);
   oldout:=word2bits (1);
   quitcmd:=false;
   initkeyboard;
   clrscr;
   writeln ('Black Knight Monitor -- keys: k kill system - n enable/disable - o open door - q quit Monitor - r refresh');
   gotoxy (1,18);
   while not ( SHMPointer^.state[S_STOP] or quitcmd ) do
    begin
     K:=PollKeyEvent; // Check for keyboard input
     if k<>0 then // Key pressed ?
      begin
       k:=TranslateKeyEvent (GetKeyEvent);
       key:= KeyEventToString (k);
       case key of
        '0': if SHMPointer^.inputs[0] then SHMPointer^.fakeinputs[0]:=false else SHMPointer^.fakeinputs[0]:=true;
        '1': if SHMPointer^.inputs[1] then SHMPointer^.fakeinputs[1]:=false else SHMPointer^.fakeinputs[1]:=true;
        '2': if SHMPointer^.inputs[2] then SHMPointer^.fakeinputs[2]:=false else SHMPointer^.fakeinputs[2]:=true;
        '3': if SHMPointer^.inputs[3] then SHMPointer^.fakeinputs[3]:=false else SHMPointer^.fakeinputs[3]:=true;
        '4': if SHMPointer^.inputs[4] then SHMPointer^.fakeinputs[4]:=false else SHMPointer^.fakeinputs[4]:=true;
        '5': if SHMPointer^.inputs[5] then SHMPointer^.fakeinputs[5]:=false else SHMPointer^.fakeinputs[5]:=true;
        '6': if SHMPointer^.inputs[6] then SHMPointer^.fakeinputs[6]:=false else SHMPointer^.fakeinputs[6]:=true;
        '7': if SHMPointer^.inputs[7] then SHMPointer^.fakeinputs[7]:=false else SHMPointer^.fakeinputs[7]:=true;
        '8': if SHMPointer^.inputs[8] then SHMPointer^.fakeinputs[8]:=false else SHMPointer^.fakeinputs[8]:=true;
        '9': if SHMPointer^.inputs[9] then SHMPointer^.fakeinputs[9]:=false else SHMPointer^.fakeinputs[9]:=true;
        'a': if SHMPointer^.inputs[10] then SHMPointer^.fakeinputs[10]:=false else SHMPointer^.fakeinputs[10]:=true;
        'b': if SHMPointer^.inputs[11] then SHMPointer^.fakeinputs[11]:=false else SHMPointer^.fakeinputs[11]:=true;
        'c': if SHMPointer^.inputs[12] then SHMPointer^.fakeinputs[12]:=false else SHMPointer^.fakeinputs[12]:=true;
        'd': if SHMPointer^.inputs[13] then SHMPointer^.fakeinputs[13]:=false else SHMPointer^.fakeinputs[13]:=true;
        'e': if SHMPointer^.inputs[14] then SHMPointer^.fakeinputs[14]:=false else SHMPointer^.fakeinputs[14]:=true;
        'f': if SHMPointer^.inputs[15] then SHMPointer^.fakeinputs[15]:=false else SHMPointer^.fakeinputs[15]:=true;
        'q': quitcmd:=true;
        'k': begin
              SHMPointer^.command:=CMD_STOP;
              SHMPointer^.SHMMSG:='Quit order given by Monitor';
              fpkill (daemonpid, SIGHUP);
             end;
        'n': begin
              if SHMPointer^.State[SC_DISABLED] then
               begin
                SHMPointer^.command:=CMD_ENABLE;
                SHMPointer^.SHMMSG:='Enabled by Monitor';
               end
              else
               begin
                SHMPointer^.command:=CMD_DISABLE;
                SHMPointer^.SHMMSG:='Disabled by Monitor';
               end;
              fpkill (daemonpid, SIGHUP);
             end;
        'o': begin
              SHMPointer^.command:=CMD_OPEN;
              SHMPointer^.SHMMSG:='Open from Monitor';
              fpkill (daemonpid, SIGHUP);
             end;
        'r': begin
              for i:=0 to 15 do
               begin
                oldout[i]:=not SHMPointer^.outputs[i];
                oldin[i]:= not SHMPointer^.inputs[i];
               end;
              writeln ('Forcing refresh');
             end;
        else writeln ('Invalid key: ',key);
       end;
      end;
     // Do some housekeeping
     debug_showbits (SHMPointer^.outputs, oldout, 0, DBGOUT);
     debug_showbits (SHMPointer^.inputs, oldin, 17, DBGIN);
     oldout:=SHMPointer^.outputs;
     oldin:=SHMPointer^.inputs;
     sleep (1);
    end;
   // Cleanup
   if quitcmd then writeln ('Quitting Monitor.')
              else writeln ('Main program stopped. Quitting as well.');
   donekeyboard;
  end;
end;

///////////// CHIP HANDLING FUNCTIONS /////////////

// Send out a word to the 74LS673
procedure write74673 (clockpin, datapin, strobepin: byte; data: TRegisterbits);
var i: byte;
begin
 for i:=0 to 15 do
 begin
  GpF.SetBit (clockpin);
  wastecpucycles (4);
  if data[i] then GpF.SetBit (datapin) else GpF.Clearbit (datapin);
  wastecpucycles (4);
  GpF.ClearBit (clockpin);
  wastecpucycles (4);
 end;
 GpF.SetBit (strobepin);
 wastecpucycles (4);
 GpF.Clearbit (strobepin);
end;

// Do an I/O cycle on the board
function io_673_150 (clockpin, datapin, strobepin, readout: byte; data:TRegisterbits): TRegisterbits;
var i: byte;
    gpioword: word;
begin
 gpioword:=0;
 for i:=0 to 15 do
  begin
   write74673 (clockpin, datapin, strobepin, word2bits ((bits2word (data) and $0fff) or (BITMIRROR[graycode (i)] shl $0c)) );
   sleep (1); // Give the electronics time for propagation
   gpioword:=(gpioword or (ord (GpF.GetBit (readout)) shl graycode(i) ) );
  end;
 io_673_150:=word2bits (gpioword);
end;

// Return true if the GPIO pins have been successfully initialized
function initgpios (clockpin, datapin, strobepin, readout: byte): boolean;
begin
 if GPIO_Driver.MapIo then
  begin
   GpF := GpIo_Driver.CreatePort(GPIO_BASE, CLOCK_BASE, GPIO_PWM);
   GpF.SetPinMode (clockpin, pigpio.OUTPUT);
   GpF.setpinmode (strobepin, pigpio.OUTPUT);
   GpF.setpinmode (datapin, pigpio.OUTPUT);
   GpF.setpinmode (readout, pigpio.INPUT);
   initgpios:=true;
  end
  else
   initgpios:=false;
end;

///////////// RUN THE FUCKING DOOR /////////////
///////////// DAEMON STUFF /////////////

procedure godaemon (daemonpid: Tpid);
var shmname: string;
    inputs, outputs : TRegisterbits;
    shmkey: TKey;
    shmid: longint;
    SHMPointer: ^TSHMVariables;
    dryrun: byte;
    open_wait, beepdelay: longint;
    open_order: boolean;
begin
 outputs:=word2bits (0);
 open_order:=false;
 dryrun:=MAXBOUNCES+2;
 fillchar (CurrentState, sizeof (CurrentState), 0);
 fillchar (msgflags, sizeof (msgflags), 0);
 fillchar (debounceinput_array, sizeof (debounceinput_array), 0);
 open_wait:=COPENWAIT; beepdelay:=0; // Initialize some timers
 CurrentState[SC_DISABLED]:=STATIC_CONFIG[SC_DISABLED]; // Get default state from config
 shmname:=paramstr (0) + #0;
 shmkey:=ftok (pchar (@shmname[1]), daemonpid);
 shmid:=shmget (shmkey, sizeof (TSHMVariables), IPC_CREAT or IPC_EXCL or 438);
 if shmid = -1 then syslog (log_err, 'Can''t create shared memory segment (pid %d). Leaving.', [daemonpid])
 else
  begin // start from a clean state
   SHMPointer:=shmat (shmid, nil, 0);
   fillchar (SHMPointer^, sizeof (TSHMVariables), 0);
   SHMPointer^.fakeinputs:=word2bits (65535);
   if initgpios (CLOCKPIN, STROBEPIN, DATAPIN, READOUTPIN) then
    CurrentState[S_DEMOMODE]:=false
   else
    begin
     syslog (log_warning,'WARNING: Error mapping registry: GPIO code disabled, running in demo mode.', []);
     CurrentState[S_DEMOMODE]:=true;
     inputs:=word2bits (65535); // Open contact = 1
    end;

   repeat
    if CurrentState[S_DEMOMODE] then // I/O cycle
     begin // Fake I/O
      inputs:=debounceinput (SHMPointer^.fakeinputs, MAXBOUNCES);
      sleep (16); // Emulate the real deal
     end
    else // Real I/O
     inputs:=debounceinput (io_673_150 (CLOCKPIN, DATAPIN, STROBEPIN, READOUTPIN, outputs), MAXBOUNCES);
    if CurrentState[S_HUP] then // Process HUP signal
     begin
      SHMPointer^.shmmsg:=SHMPointer^.shmmsg + #0; // Make sure the string is null terminated
      syslog (log_info, 'HUP received. Command: "%s" parameter: %s', [ CMD_NAME[SHMPointer^.command], @SHMPointer^.shmmsg[1]]);
      CurrentState[S_HUP]:=false; // Reset HUP signal
      case SHMPointer^.command of
       CMD_ENABLE: CurrentState[SC_DISABLED]:=false;
       CMD_DISABLE: CurrentState[SC_DISABLED]:=true;
       CMD_STOP: CurrentState[S_STOP]:=true;
       CMD_OPEN: open_order:=true;
       CMD_BEEP: beepdelay:=BUZZERCHIRP; // Small beep
      end;
      SHMPointer^.command:=CMD_NONE;
      SHMPointer^.shmmsg:='';
     end;

    if dryrun = 0 then // Make a dry run to let inputs settle
     begin
      if CurrentState[SC_DISABLED] then
       begin // System is software-disabled
        outputs:=word2bits (0); // Set all outputs to zero.
        open_order:=false;      // Deny open order (we're disabled)
       end
      else
       begin // System is enabled. Process outputs
(********************************************************************************************************)
        // Do lock logic shit !!
        if inputs[PANIC_SENSE] = IS_OPEN then
         begin // PANIC MODE (topmost priority)
          outputs[MAGLOCK1_RELAY]:=false;
          outputs[MAGLOCK2_RELAY]:=false;
          open_order:=false;
         end
        else // no panic
         begin
          if open_order or (STATIC_CONFIG[SC_HANDLE] and (inputs[DOORHANDLE] = IS_CLOSED))
           or (STATIC_CONFIG[SC_HANDLEANDLIGHT] and (inputs[LIGHTS_ON_SENSE] = IS_CLOSED) and (inputs[DOORHANDLE] = IS_CLOSED))
           or (STATIC_CONFIG[SC_DOORUNLOCKBUTTON] and (inputs[DOOR_OPEN_BUTTON] = IS_CLOSED))
           or (CurrentState[S_TUESDAY] and ((inputs[OPTO1] = IS_CLOSED) or (inputs[OPTO2] = IS_CLOSED) or (inputs[OPTO3] = IS_CLOSED))) then
           begin // Open order received
            if not busy_delay_is_expired (open_wait) and (inputs[DOOR_CLOSED_SWITCH] = IS_CLOSED) then
             begin // Open !!
              busy_delay_tick (open_wait, 16); // tick...
              open_order:=true;
//              log_door_event (LOG_MSG_SWITCHOPEN, inputs[SC_DOORUNLOCKBUTTON], msgflags, LOG_MSG, LOG_DEBUGMODE, '');
              outputs[MAGLOCK1_RELAY]:=false;
              outputs[MAGLOCK2_RELAY]:=false;
              outputs[DOOR_STRIKE_RELAY]:=true;
              outputs[BUZZER_OUTPUT]:=true;
             end
            else
             begin
              syslog (LOG_INFO, 'relocking door.', []);
              open_wait:=COPENWAIT;
              open_order:=false;
             end;
           end
          else
           begin // No open order (lock mode)
//           log_door_event (LOG_MSG_SOFTOPEN, true, msgflags, LOG_MSG, LOG_DEBUGMODE, ''); // reset log event
           if STATIC_CONFIG[SC_MAGLOCK1] and (inputs[DOOR_CLOSED_SWITCH] = IS_CLOSED) then outputs[MAGLOCK1_RELAY]:=true;
           if STATIC_CONFIG[SC_MAGLOCK2] and (inputs[DOOR_CLOSED_SWITCH] = IS_CLOSED) then outputs[MAGLOCK2_RELAY]:=true;
           outputs[DOOR_STRIKE_RELAY]:=false;
           outputs[BUZZER_OUTPUT]:=false;
           end;
         end;
       end;
(********************************************************************************************************)
      // Process beep command
      busy_delay_tick (beepdelay, 16); // tick...
      outputs[BUZZER_OUTPUT]:=(not busy_delay_is_expired (beepdelay)) or outputs[BUZZER_OUTPUT]; // The buzzer might be active elsewhere
      // Do switch monitoring

  //    syslog (log_info, 'Doing daemon shit...'#10, []);
    //  sleep (300);

(********************************************************************************************************)
      SHMPointer^.inputs:=inputs;
      SHMPointer^.outputs:=outputs;
      SHMPointer^.state:=CurrentState;
      SHMPointer^.Config:=STATIC_CONFIG;
     end
    else dryrun:=dryrun-1;
   until CurrentState[S_STOP];
  end;
 syslog (log_crit,'Daemon is exiting. Clearing outputs', []);
 outputs:=word2bits (0);
 if not CurrentState[S_DEMOMODE] then write74673 (CLOCKPIN, DATAPIN, STROBEPIN, outputs);
 sleep (100); // Give time for the monitor to die before yanking the segment
 shmctl (shmid, IPC_RMID, nil); // Destroy shared memory segment upon leaving
end;

// Fork process from main daemon and run something
function runstuff (command, parameter: string; actionindex: word): integer;
begin

end;

// Do something on signal
procedure signalhandler (sig: longint); cdecl;
begin
 case sig of
  SIGHUP: CurrentState[S_HUP]:=true;
  SIGTERM: CurrentState[S_STOP]:=true;
 end;
end;


// For IPC stuff (sending commands)
Procedure senddaemoncommand (daemonpid: TPid; cmd: byte; comment: string);
var  shmid: longint;
     shmname: string;
     shmkey: tkey;
     SHMPointer: ^TSHMVariables;
begin
 if daemonpid = 0 then
  begin
   writeln ('Daemon not started.');
   halt (1);
  end
 else
  begin
   shmname:=paramstr (0) + #0;
   shmkey:=ftok (pchar (@shmname[1]), daemonpid);
   shmid:=shmget (shmkey, sizeof (TSHMVariables), 0);
   // Add test for shmget error here ?
   SHMPointer:=shmat (shmid, nil, 0);
   writeln (paramstr (0),': Sending command ', CMD_NAME[cmd], ' to PID ', daemonpid);
   SHMPointer^.command:=cmd;
   if comment = '' then SHMPointer^.SHMMsg:='<no message provided>'
                   else SHMPointer^.SHMMsg:=comment;
   fpkill (daemonpid, SIGHUP);
  end;
end;


///////////// MAIN BLOCK /////////////
var     shmname, pidname :string;
        aOld, aTerm, aHup : pSigActionRec;
        zerosigs : sigset_t;
        ps1 : psigset;
        sSet : cardinal;
        oldpid, sid, pid: TPid;
        //shmkey,
        shmoldkey: TKey;
        shmid: longint;
        iamrunning: boolean;
        moncount: byte;

begin
 pidname:=getpidname;
 moncount:=20;
 iamrunning:=am_i_running (pidname);
 oldpid:=loadpid (pidname);

 // Clean up in case of crash or hard reboot
 if (oldpid <> 0) and not iamrunning then
  begin
   writeln ('Removing stale PID file and SHM buffer');
   deletepid (pidname);
   shmname:=paramstr (0) + #0;
   shmoldkey:=ftok (pchar (@shmname[1]), oldpid);
   shmid:=shmget (shmoldkey, sizeof (TSHMVariables), 0);
   shmctl (shmid, IPC_RMID, nil);
   oldpid:=0; // PID was stale
  end;

 case lowercase (paramstr (1)) of
  'running':   if iamrunning then halt (0) else halt (1);
  'stop':      if iamrunning then fpkill (oldpid, SIGTERM);
  'beep':      senddaemoncommand (oldpid, CMD_BEEP, paramstr (2));
  'tuesday':   senddaemoncommand (oldpid, CMD_TUESDAY, paramstr (2));
  'open':      senddaemoncommand (oldpid, CMD_OPEN, '(cmdline): ' + paramstr (2));
  'disable':   senddaemoncommand (oldpid, CMD_DISABLE, paramstr (2));
  'enable':    senddaemoncommand (oldpid, CMD_ENABLE, paramstr (2));
  'diag':      dump_config (STATIC_CONFIG, STATIC_CONFIG_STR);
  'start':
    if iamrunning
     then writeln ('Already started as PID ', oldpid)
     else
      begin
       fpsigemptyset(zerosigs);
       { block all signals except -HUP & -TERM }
       sSet := $ffffbffe;
       ps1 := @sSet;
       fpsigprocmask(sig_block,ps1,nil);
       { setup the signal handlers }
       new(aOld);
       new(aHup);
       new(aTerm);
       aTerm^.sa_handler := SigactionHandler(@signalhandler);
       aTerm^.sa_mask := zerosigs;
       aTerm^.sa_flags := 0;
       aTerm^.sa_restorer := nil;
       aHup^.sa_handler := SigactionHandler(@signalhandler);
       aHup^.sa_mask := zerosigs;
       aHup^.sa_flags := 0;
       aHup^.sa_restorer := nil;
       fpSigAction(SIGTERM,aTerm,aOld);
       fpSigAction(SIGHUP,aHup,aOld);

       pid := fpFork;
       if pid = 0 then
        Begin // we're in the child
         openlog (pchar (format (ApplicationName + '[%d]', [fpgetpid])), LOG_NOWAIT, LOG_DAEMON);
         syslog (log_info, 'Spawned new process: %d'#10, [fpgetpid]);
         Close(system.input); // close stdin
         Close(system.output); // close stdout
         Assign(system.output,'/dev/null');
         ReWrite(system.output);
         Close(stderr); // close stderr
         Assign(stderr,'/dev/null');
         ReWrite(stderr);
         FpUmask (0);
         sid:=FpSetSid;
         syslog (log_info, 'Session ID: %d'#10, [sid]);
         FpChdir ('/');
        End
       Else
        Begin // We're in the parent
         writeln (applicationname, '[',fpgetpid,']: started background process ',pid);
         SavePid(pidname, pid);
         Halt; // successful fork, so parent dies
        End;
       // Running into the daemon
       godaemon (fpgetpid);
       deletepid (pidname); // cleanup
       closelog;
      end;
  'monitor': // Interactive monitor mode
    begin
     while (not iamrunning) and (moncount <> 0) do
      begin
       moncount:=moncount-1;
       iamrunning:=am_i_running (pidname);
       writeln ('Waiting for main process to come up (',moncount,')');
       sleep (500);
      end;
     if iamrunning then
      begin
       oldpid:=loadpid (pidname);
       writeln ('Found instance running as PID ', oldpid, ', launching monitor...');
       run_test_mode (oldpid);
      end
      else
      begin
       writeln ('Main process did not start. Bailing out.');
       halt (1);
      end;
     end;
  else
   begin
    writeln ('This is the main control program for The Black Knight, HSBXL front door controller.');
    if (paramstr (1) <> '') and (lowercase (paramstr (1)) <> 'help') then writeln ('ERROR: unknown parameter: ''', paramstr (1),'''.');
    writeln;
    writeln ('Usage: ', applicationname, ' [start|stop|tuesday|monitor|open|diag|running|enable|disable] [...]');
    writeln;
    writeln ('Command line parameters:');
    writeln ('  start      - Start the daemon');
    writeln ('  stop       - Stop the daemon');
    writeln ('  tuesday    - Start open mode (not implemented yet)');
    writeln ('  monitor    - Full screen monitor for debugging');
    writeln ('  open       - Open the door. Any extra parameter is logged to syslog as extra text');
    writeln ('  diag       - Dump configuration options');
    writeln ('  beep       - Chirp the buzzer. Any extra parameter is logged to syslog as extra text');
    writeln ('  running    - For script usage: tell if the main daemon is running (check exitcode: 0=running 1=not running)');
    writeln ('  enable     - Activate the locking system outputs');
    writeln ('  disable    - Deactivate the locking system outputs. Inputs still monitored.');
    halt (1);
   end;
 end;
end.
