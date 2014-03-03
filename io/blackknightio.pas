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

uses PiGpio, sysutils, crt, keyboard, strutils, baseunix, ipc;

CONST   SHITBITS=63;

TYPE    TDbgArray= ARRAY [0..15] OF string[15];
        TRegisterbits=bitpacked array [0..15] of boolean; // Like a word: a 16 bits bitfield
        TLotsofbits=bitpacked array [0..SHITBITS] of boolean; // A shitload of bits to abuse. 64 bits should be enough. :-)
        TSHMVariables=RECORD // What items should be exposed for IPC.
                PIDofmain:TPid;
                Inputs, outputs, fakeinputs: TRegisterbits;
                state, Config :TLotsofbits;
                Command: string;
                SHMMsg:string;
//                lastcommandstatus: byte;
                end;
        TConfigTextArray=ARRAY [0..SHITBITS] of string[20];
        TLogItem=ARRAY [0..SHITBITS] OF RECORD // Log and debug text, with alternative and levels
                msglevel: byte;
                msg: string;
                altlevel: byte;
                altmsg: string;
                end;

CONST   CLOCKPIN=7;  // 74LS673 pins
        STROBEPIN=8;
        DATAPIN=25;
        READOUTPIN=4; // Output of 74150
        MAXBOUNCES=8;

        bits:array [false..true] of char=('0', '1');
        // Hardware bug: i got the address lines reversed while building the board.
        // Using a lookup table to mirror the address bits
        BITMIRROR: array[0..15] of byte=(0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15);

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
                           (msglevel: LOG_INFO; msg: ''; altlevel: LOG_NONE; altmsg: ''),
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
                           (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_ERR; msg: 'Check wiring or leaf switch: door is maglocked, but i see it open.'; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_ERR; msg: 'Check wiring or maglock 1: Disabled in config, but i see it locked.'; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_ERR; msg: 'Check wiring or maglock 2: Disabled in config, but i see it locked.'; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: ''),
                           (msglevel: LOG_NONE; msg: ''; altlevel: LOG_NONE; altmsg: '')
                           );
        // Various timers, in milliseconds (won't be accurate at all, but time is not critical)
        COPENWAIT=4000;


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
        SC_DOORSWITCH=8; SC_HANDLEANDLIGHT=9; SC_DOORUNLOCKBUTTON=10; SC_HANDLE=11;
        // Status bit block only
        S_DEMOMODE=63; S_TUESDAY=62; S_STOP=61;

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
                                             '',
                                             '', '',  '', '', '', '', '', '', '', '', '', '', '',
                                             '', '', '', '', '', '', '', '', '',  '', '', '', '', '', '', '', '', '', '',
                                             '', '', '', '', '', '', '', '', '',  '', '', '', '', '', '', '', 'Stop order', 'Tuesday mode', 'Demo mode');

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
                                    false,
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

// For IPC stuff (sending commands)
Procedure sendcommand (shmkey: TKey; cmd, comment: string);
var  shmid: longint;
     SHMPointer: ^TSHMVariables;
begin
 shmid:=shmget (shmkey, sizeof (TSHMVariables), IPC_CREAT or IPC_EXCL or 438);
    if shmid = -1 then
     begin
      shmid:=shmget (shmkey, sizeof (TSHMVariables), 0);
      // Add test for shmget error here ?
      SHMPointer:=shmat (shmid, nil, 0);
      writeln (paramstr (0),': Sending command ', cmd, ' to PID ', SHMPointer^.PIDOfMain);
      SHMPointer^.command:=cmd;
      if comment = '' then SHMPointer^.SHMMsg:='<no message provided>'
                      else SHMPointer^.SHMMsg:=comment;
     end
    else
     begin // We may have just created an instance. Killing it.
      writeln (paramstr (0),': not started.');
      shmctl (shmid, IPC_RMID, nil);
      halt (1);
     end;
end;

(*
// Rewriting the busy_delay bunch of functions
function busy_delay_calibrate: longint;
begin

end;

procedure busy_delay_init (var ;

procedure busy_delay_tick;

function busy_delay_is_expired: boolean;


*)

(*
// Buzzer functions

*)

function busy_delay (var waittime: word; timetowait: word): boolean;
begin
 case waittime of
  0:busy_delay:=true; // Time's up !!
  65535:              // Reset timer
   begin
    waittime:=timetowait shr 4; // One iteration of the loop takes 16 mS
    busy_delay:=false;
   end;
  else                // Tick...
   begin
    waittime:=waittime -1;
    busy_delay:=false;
   end;
 end;
end;

procedure busy_delay_reset (var waittime: word);
begin
 waittime:=65535;
end;

// Needed functions:  buzzer handling

// Log an event
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
function run_test_mode (SHMKey: TKey): boolean;
var  shmid: longint;
     SHMPointer: ^TSHMVariables;
     oldin, oldout: TRegisterbits;
     key: string;
     K: TKeyEvent;
     quitcmd: boolean;
     i: byte;
begin
 shmid:=shmget (shmkey, sizeof (TSHMVariables), IPC_CREAT or IPC_EXCL or 438);
 if shmid = -1 then
  begin
   run_test_mode:=true;
   shmid:=shmget (shmkey, sizeof (TSHMVariables), 0);
   // Add test for shmget error here ?
   SHMPointer:=shmat (shmid, nil, 0);
   oldin:=word2bits (0);
   oldout:=word2bits (0);
   quitcmd:=false;
   initkeyboard;
   clrscr;
   writeln (' Black Knight Monitor  -- keys: k kill system - q quit monitor - o open door - r refresh');
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
              SHMPointer^.command:='stop';
              SHMPointer^.SHMMSG:='Quit order given by monitor';
             end;
        'o': begin
              SHMPointer^.command:='open';
              SHMPointer^.SHMMSG:='Open order given by monitor';
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
   if quitcmd then writeln ('Quitting monitor.')
              else writeln ('Main program stopped. Quitting as well.');
   donekeyboard;
  end
 else
  begin // We may have just created an instance. Killing it.
   shmctl (shmid, IPC_RMID, nil);
   writeln (paramstr (0),': not started. Waiting for startup...');
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

///////////// RUN THE FUCKING DOOR /////////////

// Spaghetti code warning !!
// This is the dirtiest function: need a rewrite. It is not maintainable.
procedure run_door (shmkey: TKey);
var  shmid: longint;
     inputs, outputs : TRegisterbits;
     SHMPointer: ^TSHMVariables;
     CurrentState, msgflags: TLotsOfBits;
     open_wait: word;
     opendoor, i, dryrun: byte; // A boolean can be used, but is very sketchy
begin
 shmid:=shmget (shmkey, sizeof (TSHMVariables), IPC_CREAT or IPC_EXCL or 438);
 if shmid = -1 then
  begin
   writeln (paramstr (0),': not starting: already running.');
   halt (1);
  end;
 SHMPointer:=shmat (shmid, nil, 0);
 fillchar (SHMPointer^, sizeof (TSHMVariables), 0);
 SHMPointer^.PIDOfMain:=fpGetPid;
 SHMPointer^.fakeinputs:=word2bits (65535);
 outputs:=word2bits (0);
 dryrun:=MAXBOUNCES+2;
 fillchar (CurrentState, sizeof (CurrentState), 0);
 fillchar (msgflags, sizeof (msgflags), 0);
 fillchar (debounceinput_array, sizeof (debounceinput_array), 0);
// for i:=0 to 15 do debounceinput_array[true][i]:=MAXBOUNCES;
 opendoor:=0;
 busy_delay_reset (open_wait);
 if GPIO_Driver.MapIo then
  begin
   CurrentState[S_DEMOMODE]:=false;
   GpF := GpIo_Driver.CreatePort(GPIO_BASE, CLOCK_BASE, GPIO_PWM);
   GpF.SetPinMode (CLOCKPIN, OUTPUT);
   GpF.setpinmode (STROBEPIN, OUTPUT);
   GpF.setpinmode (DATAPIN, OUTPUT);
   GpF.setpinmode (READOUTPIN, INPUT);
  end
  else
  begin
   writeln ('WARNING: Error mapping registry: GPIO code disabled, running in demo mode.');
   CurrentState[S_DEMOMODE]:=true;
   inputs:=word2bits (65535); // Open contact = 1
  end;
 log_door_event (LOG_MSG_START, false, msgflags, LOG_MSG, LOG_DEBUGMODE, '');

 repeat // Start of the main loop. Should run at around 62,5 Hz. The I/O operation has a hard-coded 16 ms delay (propagation time through the I/O chips)
  if CurrentState[S_DEMOMODE] then
   begin
    inputs:=debounceinput (SHMPointer^.fakeinputs, MAXBOUNCES);
    sleep (16); // Emulate the real deal
   end
   else
    inputs:=debounceinput (io_673_150 (CLOCKPIN, DATAPIN, STROBEPIN, READOUTPIN, outputs), MAXBOUNCES);

  if dryrun = 0 then // Make a dry run to let inputs settle
   begin
(********************************************************************************************************)

     // Do lock logic shit !!
     if inputs[PANIC_SENSE] = IS_OPEN then
      begin // PANIC MODE (topmost priority)
       outputs[MAGLOCK1_RELAY]:=false;
       outputs[MAGLOCK2_RELAY]:=false;
       if SHMPointer^.command <> 'stop' then SHMPointer^.command:=''; // Deny any other command
      end
      else
      begin
       if SHMPointer^.command = 'open' then
        begin
         opendoor:=255;
         log_door_event (LOG_MSG_SOFTOPEN, false, msgflags, LOG_MSG, LOG_DEBUGMODE, SHMPointer^.SHMMSG);
         SHMPointer^.command:='';
        end;

       if (opendoor = 255) or (STATIC_CONFIG[SC_HANDLE] and (inputs[DOORHANDLE] = IS_CLOSED))
          or (STATIC_CONFIG[SC_HANDLEANDLIGHT] and (inputs[LIGHTS_ON_SENSE] = IS_CLOSED) and (inputs[DOORHANDLE] = IS_CLOSED))
          or (STATIC_CONFIG[SC_DOORUNLOCKBUTTON] and (inputs[DOOR_OPEN_BUTTON] = IS_CLOSED))
          or (CurrentState[S_TUESDAY] and ((inputs[OPTO1] = IS_CLOSED) or (inputs[OPTO2] = IS_CLOSED) or (inputs[OPTO3] = IS_CLOSED))) then
        begin

         // somewhat sketchy below
         if not busy_delay (open_wait, COPENWAIT) then
          begin
           opendoor:=255;
           log_door_event (LOG_MSG_SWITCHOPEN, inputs[SC_DOORUNLOCKBUTTON], msgflags, LOG_MSG, LOG_DEBUGMODE, '');
           outputs[MAGLOCK1_RELAY]:=false;
           outputs[MAGLOCK2_RELAY]:=false;
           outputs[DOOR_STRIKE_RELAY]:=true;
           outputs[BUZZER_OUTPUT]:=true;
          end
          else
          begin
           writeln ('relocking door.');
           busy_delay_reset (open_wait);
           opendoor:=0;
          end;
        end
        else
        begin
         log_door_event (LOG_MSG_SOFTOPEN, true, msgflags, LOG_MSG, LOG_DEBUGMODE, ''); // reset log event
         if STATIC_CONFIG[SC_MAGLOCK1] then outputs[MAGLOCK1_RELAY]:=true;
         if STATIC_CONFIG[SC_MAGLOCK2] then outputs[MAGLOCK2_RELAY]:=true;
         outputs[DOOR_STRIKE_RELAY]:=false;
         outputs[BUZZER_OUTPUT]:=false;
       end;
       // somewhat sketchy above
      end;
     // End of lock logic shit.

     // Leaf switch: sketchy
//     if STATIC_CONFIG[SC_DOORSWITCH] then
//      log_door_event (LOG_MSG_DOORLEAFSWITCH, inputs[DOOR_CLOSED_SWITCH] = IS_CLOSED , msgflags, LOG_MSG, LOG_DEBUGMODE, '');

     // Panic logging
     log_door_event (LOG_MSG_PANIC, not inputs[PANIC_SENSE] , msgflags, LOG_MSG, LOG_DEBUGMODE, '');
     // Tamper processing
     if STATIC_CONFIG[SC_TRIPWIRE_LOOP] then
      log_door_event (LOG_MSG_TRIPWIRE, inputs[TRIPWIRE_LOOP] = IS_CLOSED , msgflags, LOG_MSG, LOG_DEBUGMODE, '');
     if STATIC_CONFIG[SC_BOX_TAMPER_SWITCH] then
      log_door_event (LOG_MSG_BOXTAMPER, inputs[BOX_TAMPER_SWITCH] = IS_CLOSED , msgflags, LOG_MSG, LOG_DEBUGMODE, '');
     // Check mail
     if STATIC_CONFIG[SC_MAILBOX] then
      log_door_event (LOG_MSG_MAIL, inputs[MAILBOX] = IS_OPEN , msgflags, LOG_MSG, LOG_DEBUGMODE, '');
     // Hallway light logging
     if STATIC_CONFIG[SC_HALLWAY] then
      log_door_event (LOG_MSG_HALLWAYLIGHT, inputs[LIGHTS_ON_SENSE] = IS_OPEN , msgflags, LOG_MSG, LOG_DEBUGMODE, '');

(********************************************************************************************************)
      // Return current state to the shm buffer
      if SHMPointer^.command = 'stop' then
       begin
        SHMPointer^.command:='';
        outputs:=word2bits (0);
        CurrentState[S_STOP]:=true;
        if not CurrentState[S_DEMOMODE] then write74673 (CLOCKPIN, DATAPIN, STROBEPIN, outputs);
       end;
      SHMPointer^.inputs:=inputs;
      SHMPointer^.outputs:=outputs;
      SHMPointer^.state:=CurrentState;
      SHMPointer^.Config:=STATIC_CONFIG;
   end
   else dryrun:=dryrun-1;
 until CurrentState[S_STOP];
 // Cleaning up
 log_door_event (LOG_MSG_STOP, false, msgflags, LOG_MSG, LOG_DEBUGMODE, SHMPointer^.shmmsg);
 shmctl (shmid, IPC_RMID, nil);
end;


///////////// MAIN BLOCK /////////////
var     progname:string;
        shmkey: TKey;
        shmid: longint;
begin
 progname:=paramstr (0) + #0;
 shmkey:=ftok (pchar (@progname[1]), ord ('t'));

 case paramstr (1) of
  'stop':
    sendcommand (shmkey, 'stop', paramstr (2));
  'tuesday':
    sendcommand (shmkey, 'tuesday', paramstr (2));
  'open':
    sendcommand (shmkey, 'open', 'commandline: ' + paramstr (2));
  'start':
    run_door (shmkey);
  'monitor': // Interactive monitor mode
    repeat
     sleep (500);
    until run_test_mode (shmkey);
  'forget':
    begin
     writeln ('Forgetting everything about my running processes (NOT RECOMMENDED)');
     shmid:=shmget (shmkey, sizeof (TSHMVariables), 0);
     shmctl (shmid, IPC_RMID, nil);
    end;
  'diag':
    begin
     dump_config (STATIC_CONFIG, STATIC_CONFIG_STR);
    end;
  '':
   begin
    writeln ('Usage: ', paramstr (0), ' [start|stop|tuesday|monitor|open|diag]');
    halt (1);
   end;
 end;
end.
