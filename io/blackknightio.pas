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

uses PiGpio, sysutils, crt, keyboard, strutils, baseunix, ipc, systemlog, pidfile, unix, chip7400, typinfo;

CONST   SHITBITS=22; // Should go away at some point

TYPE    TDbgArray= ARRAY [0..15] OF string[15];
        TLotsofbits=bitpacked array [0..SHITBITS] of boolean; // A shitload of bits to abuse. 64 bits should be enough. :-) Should go away at some point.
        // Available commands for IPC (subject to change)
        TCommands=(CMD_NONE, CMD_OPEN, CMD_TUESDAY_START, CMD_TUESDAY_STOP, CMD_ENABLE, CMD_DISABLE, CMD_BEEP, CMD_LIGHT, CMD_STOP);
        TBusyBuzzerScratch=RECORD
                TimeIndex: longint;
                offset: longint;
                end;
        TBuzzPattern= ARRAY [0..20] OF LONGINT;
        // Door states
        Tdoorstates=(DS_ENTRY, DS_LOG_DISABLED, DS_DISABLED, DS_LOG_ENABLED, DS_ENABLED, DS_LOG_PANIC, DS_PANIC, DS_LOG_OPEN, DS_OPEN, DS_LOG_CLOSED, DS_CLOSED,
                  DS_NONE, DS_LOG_LOCKED, DS_LOCKED, DS_UNLOCKED, DS_LOG_PARTIAL1, DS_PARTIAL1, DS_LOG_PARTIAL2, DS_PARTIAL2, DS_NOT_LOCKED, DS_LOG_NOW_LOCKED,
                  DS_LOG_NOMAG, DS_NOMAG, DS_LOG_MAG1_NOT_LOCKED, DS_LOG_MAG2_NOT_LOCKED, DS_LOG_2MAGS_NOT_LOCKED, DS_NOT_CLOSED, DS_LOG_STAY_WIDE_OPEN,
                  DS_STAY_WIDE_OPEN, DS_LOG_UNLOCK_SYSTEM, DS_LOG_UNLOCK_MONITOR, DS_LOG_UNLOCK_CMDLINE, DS_LOG_UNLOCK_HANDLEANDLIGHT, DS_LOG_UNLOCK_DOORBELL,
                  DS_LOG_UNLOCK_HANDLE);
        // Available error messages
        TLogItems=(MSG_DEMO, MSG_SYS_DISABLED, MSG_SYS_ENABLED, MSG_PANIC, MSG_MAG1PARTIAL, MSG_MAG2PARTIAL, MSG_2MAGS_NOLATCH, MSG_MAG1_NOLATCH,
                   MSG_MAG2_NOLATCH, MSG_NOMAG_CFG, MSG_CLOSED_NOMAG, MSG_NOW_LOCKED, MSG_DOORISLOCKED, MSG_DOORISOPEN, MSG_DOORISCLOSED,
                   MSG_MAILBOX, MSG_MAILBOX_THANKS, MSG_TRIPWIRE, MSG_BOX_TAMPER, MSG_MAG1_WIRING, MSG_MAG2_WIRING, MSG_MAG1_DISABLED_BUT_CLOSED,
                   MSG_MAG2_DISABLED_BUT_CLOSED, MSG_TUESDAY_INACTIVE, MSG_TUESDAY_ACTIVE, MSG_LIGHT_ON, MSG_OPEN_BUTTON,
                   MSG_OPEN_HANDLE_AND_LIGHT, MFS_FORBIDDEN_HANDLE, MSG_OPEN_HANDLE, MSG_OPEN_SYSTEM, MSG_OPEN_DOORBELL, MSG_DOORBELL, MSG_DOORSWITCH_FAIL, MSG_MAG1_FAIL,
                   MSG_MAG2_FAIL, MSG_BAILOUT, MSG_DOORBELL_STUCK, MSG_DOORBELL_FIXED, MSG_DOOROPENBUTTON_STUCK, MSG_DOOROPENBUTTON_FIXED, MSG_HANDLE_STUCK, MSG_HANDLE_FIXED);
        TLogItemText= ARRAY[TLogItems] of pchar;
        // Simple universal state machine definition (let's see how far it flies)
        TSimpleSM=(SM_ENTRY, SM_ACTIVE, SM_LOG_OPEN, SM_OPEN, SM_LOG_REALLY_OPEN, SM_REALLY_OPEN, SM_LOG_CLOSED, SM_CLOSED, SM_LOG_REALLY_CLOSED,
                   SM_REALLY_CLOSED, SM_LOG_STUCK_CLOSED, SM_STUCK_CLOSED, SM_LOG_UNSTUCK);
        // Tuesday mode state machine
        TTuesdaySM=(SM_OFF, SM_LOG_START, SM_START, SM_TICK, SM_LOG_STOP);

        TConfigTextArray=ARRAY [0..SHITBITS] of string[20]; // Should go away at some point
        TSHMVariables=RECORD // What items should be exposed for IPC.
                Inputs, outputs, fakeinputs: TRegisterbits;
                DoorState: TDoorStates;
                TuesdayState: TTuesdaySM;
                MailboxState, TamperState, TripwireState: TSimpleSM;
                state, Config :TLotsofbits;
                senderpid: TPid;
                Command: TCommands;
                SHMMsg:string;
                end;

CONST   CLOCKPIN=7;  // 74LS673 pins
        STROBEPIN=8;
        DATAPIN=25;
        READOUTPIN=4; // Output of 74150
        MAXBOUNCES=8;
        VCAP_LOAD_RATE=4;  // Virtual capacitor to eat the 50 Hz ripple on the opto inputs
        VCAP_UNLOAD_RATE=2;

        CMD_NAME: ARRAY [TCommands] of pchar=('NoCMD','open','tuesday_start','tuesday_end','enable','disable','beep','lights_on','stop');

        LOG_ITEM_TEXT_EN: TLogItemText=('WARNING: Error mapping registry: GPIO code disabled, running in demo mode.',
                                        'Door System is disabled in software',
                                        'Door System is enabled',
                                        'PANIC BUTTON PRESSED: MAGNETS ARE DISABLED',
                                        'Partial lock detected: Maglock 2 did not latch.',
                                        'Partial lock detected: Maglock 1 did not latch.',
                                        'No maglock latched: Door is not locked.',
                                        'Maglock 1 did not latch: Door is not locked',
                                        'Maglock 2 did not latch: Door is not locked',
                                        'No magnetic lock installed. This configuration is NOT recommended.',
                                        'Door is closed. Cannot see if it is locked',
                                        'Door is now locked. Thank you.',
                                        'Door is locked.',
                                        'Door is open',
                                        'Door is closed',
                                        'There is mail in the mailbox',
                                        'Thank you for clearing the mail',
                                        'TRIPWIRE LOOP BROKEN: POSSIBLE BREAK-IN',
                                        'Control box is being opened',
                                                  'Check maglock 1 and it''s wiring: maglock is off but i see it closed',
                                                  'Check maglock 2 and it''s wiring: maglock is off but i see it closed',
                                                  'Wiring error: maglock 1 is disabled in configuration but i see it closed',
                                                  'Wiring error: maglock 2 is disabled in configuration but i see it closed',
                                        'Tuesday mode inactive',
                                        'Tuesday mode active. Ring doorbell to enter',
                                        'Hallway light is on',
                                        'Door opened from button',
                                        'Door opened from handle with the light on',
                                                'You are not allowed to use the handle',
                                        'Door opened from handle',
                                        'Order from system',
                                        'Tuesday mode: door opened by doorbell',
                                        'Ding Ding Dong',
                                                  'Check wiring of door switch: door is locked but i see it open',
                                                  'Magnetic lock 1 or its wiring failed. Please repair.',
                                                  'Magnetic lock 2 or its wiring failed. Please repair.',
                                        'Door controller is bailing out. Clearing outputs',
                                                'The doorbell button is stuck. Doorbell notifications disabled. Please repair.',
                                                'The doorbell button is now fixed. Notifications re-activated. Thank you.',
                                        'The door open button is stuck closed and has been disabled. Please repair.',
                                        'The door open button has been released. Reactivating.',
                                                'The handle is stuck. Handle control disabled. Please repair.',
                                                'The handle has been fixed. Reactivating.');

        // Hardware bug: i got the address lines reversed while building the board.
        // Using a lookup table to mirror the address bits
        BITMIRROR: array[0..15] of byte=(0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15);
        // Various timers, in milliseconds (won't be accurate at all, but time is not critical)
        COPENWAIT=4000; // How long to leave the door unlocked after receiving open order
        LOCKWAIT=2000;  // Maximum delay between leaf switch closure and maglock feedback switch closure (if delay expired, alert that the door is not closed properly
        MAGWAIT=1500;   // Reaction delay of the maglock output relay (the PCB has capacitors)
        BUZZERCHIRP=150; // Small beep delay
        TUESDAY_DEFAULT_TIME=1000*60*60*3; // tuesday timer: 3 hours
        LOG_REPEAT_RATE_FAST=1000*10; // Repeat that error every 10 seconds
        LOG_REPEAT_RATE_SLOW=LOG_REPEAT_RATE_FAST*60; // Repeat that error every 6 minutes
        SND_MISTERCASH: TBuzzPattern=(50, 100, 50, 100, 50, 100, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
        SND_DOORNOTCLOSED: TBuzzPattern=(32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, -1); // Be a noisy asshole
        // Places to look for the external script
        SCRIPTNAMES: array [0..5] of string=('/etc/blackknightio/blackknightio.sh',
                                             '/usr/local/etc/blackknightio/blackknightio.sh',
                                             '/usr/local/etc/blackknightio.sh',
                                             '/usr/local/bin/blackknightio.sh',
                                             '/usr/bin/blackknightio.sh',
                                             '/root/blackknightio.sh');

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
//        DBGINSTATESTR: Array [IS_CLOSED..IS_OPEN] of string[5]=('closed', 'open');
//        DBGOUTSTATESTR: Array [false..true] of string[5]=('On', 'Off');
        CFGSTATESTR: Array [false..true] of string[8]=('Disabled','Enabled');
        DBGOUT: TDbgArray=('Green LED', 'Red LED', 'Q13 not used', 'Q12 not used', 'relay not used', 'strike', 'mag1 power', 'mag2 power', 'not used',
                                'light', 'bell inhib.', 'Buzzer', '74150 A3', '74150 A2', '74150 A1', '74150 A0');
        DBGIN: TDbgArray=('TAMPER BOX','MAG1 CLOSED','MAG2 CLOSED','IN 8','IN 7','Light on sense','door closed','Handle',
                          'Mailbox','Tripwire','opendoorbtn','PANIC SWITCH','DOORBELL 1','DOORBELL 2','DOORBELL 3','OPTO 4');
        // offsets in status/config bitfields
        SC_MAGLOCK1=0; SC_MAGLOCK2=1; SC_TRIPWIRE_LOOP=2; SC_BOX_TAMPER_SWITCH=3; SC_MAILBOX=4; SC_BUZZER=5; SC_BATTERY=6; SC_HALLWAY=7;
        SC_HANDLEANDLIGHT=8; SC_DOORUNLOCKBUTTON=9; SC_HANDLE=10; SC_DISABLED=11; SC_HOLDER=12; SC_BUZZER_DOORBELL=13;
        // Status bit block only. This should hopefully go away
        S_DEMOMODE=20; S_STOP=21; S_HUP=22;

        // Static config
        STATIC_CONFIG_STR: TConfigTextArray=('Maglock 1',
                                             'Maglock 2',
                                             'Tripwire loop',
                                             'Box tamper',
                                             'Mail notification',
                                             'buzzer',
                                             'Backup Battery',
                                             'Hallway lights',
                                             'handle+light unlock',
                                             'Door unlock button',
                                             'Handle unlock only',
                                             'Software-disabled',
                                             'Hold-open device',
                                             'Buzzer-as-doorbell',
                                             '',
                                             '', '', '', '',
                                             '',  'HUP received', 'Stop order', 'Demo mode');

        STATIC_CONFIG: TLotsOfBits=(false,  // SC_MAGLOCK1 (Maglock 1 installed)
                                    true, // SC_MAGLOCK2 (Maglock 2 not installed)
                                    false,  // SC_TRIPWIRE_LOOP (Tripwire not installed)
                                    false,  // SC_BOX_TAMPER_SWITCH (Tamper switch installed)
                                    true,  // SC_MAILBOX (Mail detection installed)
                                    true,  // SC_BUZZER (Let it make some noise)
                                    false, // SC_BATTERY (battery not attached)
                                    false, // SC_HALLWAY (Hallway light not connected)
                                    true,  // SC_HANDLEANDLIGHT (The light must be on to unlock with the handle)
                                    true,  // SC_DOORUNLOCKBUTTON (A push button to open the door)
                                    false, // SC_HANDLE (Unlock with the handle only: not recommended in HSBXL)
                                    false, // SC_DISABLED (system is software-disabled by default)
                                    false, // SC_HOLDER (magnet to hold the door open while entering with a bike)
                                    true, // SC_BUZZER_DOORBELL (The buzzer is used as a doorbell)
                                    false,
                                    false, false, false,
                                    false,
                                    false, // Unused
                                    false, // Unused
                                    false, // Unused
                                    false  // Unused
                                    );

VAR     GPIO_Driver: TIODriver;
        GpF: TIOPort;
        debounceinput_array: ARRAY[false..true, 0..15] of byte; // That one has to be global. No way around it.
        B_DEMOMODE, B_HUP, B_STOP: boolean;     // Reason for global: it is modified by the signal handler
        CurrentState: TLotsOfBits;   // Reason for global: it is modified by the signal handler
        LockBuzzerTracker, BuzzerTracker: TBusyBuzzerScratch;

///////////// COMMON LIBRARY FUNCTIONS /////////////

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

// Decrement the timer variable
procedure busy_delay_tick (var waitvar: longint; ticklength: word);
begin
 if waitvar >= 0 then waitvar:=waitvar - ticklength else waitvar:=0;
end;

// Is the timer expired ?
function busy_delay_is_expired (var waitvar: longint): boolean;
begin
 if waitvar <= 0 then busy_delay_is_expired:=true
                 else busy_delay_is_expired:=false;
end;

// Play a beep pattern
function busy_buzzer (var scratchspace: TBusyBuzzerScratch; pattern: TBuzzpattern; ticklength: word): boolean;
begin
 if (pattern[scratchspace.offset] = 0) or (pattern[scratchspace.offset] = -1) then busy_buzzer:=false // End of pattern: shut up.
  else
  begin
   if (scratchspace.TimeIndex <= 0) then scratchspace.TimeIndex:=pattern[scratchspace.offset];
   busy_buzzer:=((scratchspace.offset and 1) = 1);// Beep !!
   busy_delay_tick (scratchspace.TimeIndex, ticklength);
   if busy_delay_is_expired (scratchspace.TimeIndex) then
    begin
     inc (scratchspace.offset); // Next !!
     if pattern[scratchspace.offset] = -1 then scratchspace.offset:=0; // Did we ask pattern repetition ?
     scratchspace.TimeIndex:=pattern[scratchspace.offset];
    end;
  end
end;

// Log a single event and run external script
procedure log_single_door_event (msgindex: TLogItems; msgtext: TLogItemText; extratext: pchar);
var pid: Tpid;
    enumnamestr: string;
begin
 enumnamestr:=GetEnumName (typeinfo (TLogItems), ord (msgindex)) + #0;
 syslog (log_warning, '%s: %s (%s)', [ @enumnamestr[1], msgtext[msgindex], extratext]);
 pid:=fpFork;
 if pid = 0 then
  begin
   fpexecl (paramstr (0) + '.sh', [ enumnamestr, msgtext[msgindex], extratext] );
   syslog (LOG_WARNING, 'Process returned: error code: %d', [FpGetErrNo]);
   halt(0);
  end;
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
// This will need a substantial rewrite
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
              SHMPointer^.senderpid:=FpGetPid;
              fpkill (daemonpid, SIGHUP);
             end;
        'n': begin // BUG here
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
              SHMPointer^.senderpid:=FpGetPid;
              fpkill (daemonpid, SIGHUP);
             end;
        'o': begin
              SHMPointer^.command:=CMD_OPEN;
              SHMPointer^.SHMMSG:='Open from Monitor';
              SHMPointer^.senderpid:=FpGetPid;
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

// The full screen shell is difficult to use in a script.
// Still need to figure out how to implement this.
procedure debug_shell;
const shell_prefix='blackknightio >>';
      runningstr:array [false..true] of string=('no','yes');
var cmd: string;
begin
 repeat
  write (shell_prefix); readln (cmd);
  case cmd of
   'help':      writeln ('Available commands: exit help quit running');
   'start':     writeln ('Add code for function ',cmd);
   'stop':      writeln ('Add code for function ',cmd);
   'running':   writeln ('Add code for function ',cmd);
   'disable':      writeln ('Add code for function ',cmd);
   'enable':      writeln ('Add code for function ',cmd);
   'open':      writeln ('Add code for function ',cmd);
   'beep':      writeln ('Add code for function ',cmd);
  end;
 until (cmd='exit') or (cmd='quit');
end;

///////////// CALLBACKS FOR UNIT CHIP7400 /////////////
// These procedures know how to *access* the chips, but not how to talk to them.

procedure setregclock (state: boolean);
begin
 if state then GpF.SetBit (CLOCKPIN) else GpF.ClearBit (CLOCKPIN);
end;

procedure setregdata (state: boolean);
begin
 if state then GpF.SetBit (DATAPIN) else GpF.ClearBit (DATAPIN);
end;

procedure setregstrobe (state: boolean);
begin
 if state then GpF.SetBit (STROBEPIN) else GpF.ClearBit (STROBEPIN);
end;

function getgpioinput: boolean;
begin
 getgpioinput:=GpF.GetBit (READOUTPIN);
end;

///////////// CHIP HANDLING FUNCTIONS /////////////

// Do an I/O cycle on the board
function io_673_150 (data:TRegisterbits): TRegisterbits;
var i: byte;
    gpioword: word;
begin
 gpioword:=0;
 for i:=0 to 15 do
  begin
   ls673_write (@setregclock, @setregdata, @setregstrobe, word2bits ((bits2word (data) and $0fff) or (BITMIRROR[graycode (i)] shl $0c)) );
   sleep (1); // Give the electronics time for propagation
   gpioword:=(gpioword or (ord (GetGPIOinput) shl graycode(i) ) );
  end;
 io_673_150:=word2bits (gpioword);
end;

// Return true if the GPIO pins have been successfully initialized
function initgpios (clockpin, datapin, strobepin, readout: byte): boolean;
begin
 Gpio_Driver:=TIODriver.create;
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
    doorstate: TDoorstates;
    tuesdaystate: TTuesdaySM;
    MailboxSM, TripwireSM, TamperSM, DoorbellSM, PresenceSM, OpenButtonSM, HandleSM: TSimpleSM;
    open_wait, tuesdaytimer, beepdelay, Mag1CloseWait, Mag2CloseWait, Mag1LockWait, Mag2LockWait: longint;
begin
 outputs:=word2bits (0); // Set all outputs to zero.
 doorstate:=DS_ENTRY; MailboxSM:=SM_ENTRY; TripwireSM:=SM_ENTRY; TamperSM:=SM_ENTRY; DoorbellSM:=SM_ENTRY; // Initialize the state machines
 PresenceSM:=SM_ENTRY; OpenButtonSM:=SM_ENTRY; HandleSM:=SM_ENTRY; tuesdaystate:=SM_OFF;
 dryrun:=MAXBOUNCES+2;
 open_wait:=0; beepdelay:=0; Mag1CloseWait:=MAGWAIT; Mag2CloseWait:=MAGWAIT; Mag1LockWait:=LOCKWAIT; Mag2LockWait:=LOCKWAIT; // Initialize some timers
 fillchar (CurrentState, sizeof (CurrentState), 0);
 fillchar (debounceinput_array, sizeof (debounceinput_array), 0);
 fillchar (buzzertracker, sizeof (buzzertracker), 0);
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
     log_single_door_event (MSG_DEMO, LOG_ITEM_TEXT_EN, '');
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
      inputs:=debounceinput (io_673_150 (outputs), MAXBOUNCES);
    if CurrentState[S_HUP] then // Process HUP signal
     begin
      SHMPointer^.shmmsg:=SHMPointer^.shmmsg + #0; // Make sure the string is null terminated
      syslog (log_info, 'HUP received from PID %d. Command: "%s" with parameter: "%s"', [ SHMPointer^.senderpid, CMD_NAME[SHMPointer^.command], @SHMPointer^.shmmsg[1]]);
      case SHMPointer^.command of
       CMD_ENABLE: if doorstate=DS_DISABLED then doorstate:=DS_LOG_ENABLED;
       CMD_DISABLE: if doorstate<>DS_DISABLED then doorstate:=DS_LOG_DISABLED;
       CMD_STOP: CurrentState[S_STOP]:=true;
       CMD_OPEN: if (doorstate=DS_PARTIAL1) or (doorstate=DS_PARTIAL2) or (doorstate=DS_LOCKED) or (doorstate=DS_NOMAG) then doorstate:=DS_LOG_UNLOCK_SYSTEM;
       CMD_BEEP: beepdelay:=BUZZERCHIRP; // Small beep
       CMD_TUESDAY_START: tuesdaystate:=SM_LOG_START; // Start tuesday timer
       CMD_TUESDAY_STOP: tuesdaystate:=SM_LOG_STOP; // Early stop of the tuesday mode
      end;
      SHMPointer^.command:=CMD_NONE;
      CurrentState[S_HUP]:=false; // Reset HUP signal
      SHMPointer^.senderpid:=0; // Reset sender PID: If zero, we may have a race condition
     end;

    // Panic mode has topmost priority
    if (inputs[PANIC_SENSE] = IS_OPEN) and (doorstate<> DS_PANIC) and (dryrun = 0) then doorstate:=DS_LOG_PANIC;

    // Start of tuesday mode state machine
    case tuesdaystate of
     SM_OFF: tuesdaytimer:=0; // Tuesday mode is off
     SM_LOG_START: // Start the tuesday timer
      begin
       log_single_door_event (MSG_TUESDAY_ACTIVE, LOG_ITEM_TEXT_EN, '');
       tuesdaystate:=SM_START;
      end;
     SM_START:
      begin
       tuesdaytimer:=TUESDAY_DEFAULT_TIME;
       tuesdaystate:=SM_TICK;
      end;
     SM_TICK: //Tick the tuesday timer
      begin
       if tuesdaytimer=0 then tuesdaystate:=SM_LOG_STOP;
       busy_delay_tick (tuesdaytimer, 16);
      end;
     SM_LOG_STOP: // stop the timer
      begin
       log_single_door_event (MSG_TUESDAY_INACTIVE, LOG_ITEM_TEXT_EN, '');
       tuesdaystate:=SM_OFF;
      end;
    end;
    // End of tuesday mode state machine

    // Start of front door state machine
    case doorstate of
     DS_ENTRY: // First thing to run
      begin
       if dryrun = 0 then if STATIC_CONFIG[SC_DISABLED] then doorstate:=DS_DISABLED else doorstate:=DS_ENABLED
                     else dryrun:=dryrun - 1;
      end;
     DS_LOG_DISABLED: // Log the door disabled event
      begin
       log_single_door_event (MSG_SYS_DISABLED, LOG_ITEM_TEXT_EN, '');
       doorstate:=DS_DISABLED;
      end;
     DS_DISABLED: // System disabled
      begin
       outputs:=word2bits (0); // Set all outputs to zero.
      end;
     DS_LOG_ENABLED: // Log the door enabled event
      begin
       log_single_door_event (MSG_SYS_ENABLED, LOG_ITEM_TEXT_EN, '');
       if (not STATIC_CONFIG[SC_MAGLOCK1]) and (not STATIC_CONFIG[SC_MAGLOCK2]) then log_single_door_event (MSG_NOMAG_CFG, LOG_ITEM_TEXT_EN, '');
       doorstate:=DS_ENABLED;
      end;
     DS_ENABLED: // System enabled
      begin
       if inputs[DOOR_CLOSED_SWITCH] = IS_CLOSED then doorstate:=DS_CLOSED else doorstate:=DS_OPEN;
      end;
     DS_LOG_PANIC: // Log the panic event
      begin
       log_single_door_event (MSG_PANIC, LOG_ITEM_TEXT_EN, '');
       doorstate:=DS_PANIC;
      end;
     DS_PANIC: // In panic mode
      begin
       outputs[MAGLOCK1_RELAY]:=false;
       outputs[MAGLOCK2_RELAY]:=false;
       if inputs[PANIC_SENSE] = IS_CLOSED then // Leave panic mode
        if STATIC_CONFIG[SC_DISABLED] then doorstate:=DS_DISABLED // BUG: It should resume from the previous state
                                      else doorstate:=DS_ENABLED;
      end;
     DS_LOG_OPEN:
      begin
       log_single_door_event (MSG_DOORISOPEN, LOG_ITEM_TEXT_EN, '');
       doorstate:=DS_OPEN;
      end;
     DS_OPEN: // Door is open
      begin
       if inputs[DOOR_CLOSED_SWITCH] = IS_CLOSED then doorstate:=DS_CLOSED;
       outputs[BUZZER_OUTPUT]:=false;
       outputs[DOOR_STRIKE_RELAY]:=false;
       Mag1LockWait:=LOCKWAIT;
       Mag2LockWait:=LOCKWAIT;
      end;
     DS_LOG_CLOSED:
      begin
       log_single_door_event (MSG_DOORISCLOSED, LOG_ITEM_TEXT_EN, '');
       doorstate:=DS_CLOSED;
      end;
     DS_CLOSED: // Door is closed
      begin
       if STATIC_CONFIG[SC_MAGLOCK1] then outputs[MAGLOCK1_RELAY]:=true;
       if STATIC_CONFIG[SC_MAGLOCK2] then outputs[MAGLOCK2_RELAY]:=true;
       outputs[DOOR_STRIKE_RELAY]:=false;
       fillchar (buzzertracker, sizeof (buzzertracker), 0);
       open_wait:=COPENWAIT;
       // Start the closing timers. Stop ticking when the shoe is on the magnet -> door is locked.
       if (inputs[MAGLOCK1_RETURN] = IS_OPEN) then busy_delay_tick (Mag1LockWait, 16);
       if (inputs[MAGLOCK2_RETURN] = IS_OPEN) then busy_delay_tick (Mag2LockWait, 16);
       if STATIC_CONFIG[SC_MAGLOCK1] and (not STATIC_CONFIG[SC_MAGLOCK2]) then  // Mag 1 only
        begin
         if (inputs[MAGLOCK1_RETURN] = IS_CLOSED) then doorstate:=DS_LOG_LOCKED;
         if busy_delay_is_expired (mag1lockwait) and (inputs[MAGLOCK1_RETURN] = IS_OPEN) then doorstate:=DS_LOG_MAG1_NOT_LOCKED; // Magnet 1 did not lock
        end;
       if (not STATIC_CONFIG[SC_MAGLOCK1]) and STATIC_CONFIG[SC_MAGLOCK2] then // Mag 2 only
        begin
         if (inputs[MAGLOCK2_RETURN] = IS_CLOSED) then doorstate:=DS_LOG_LOCKED;
         if busy_delay_is_expired (mag2lockwait) and (inputs[MAGLOCK2_RETURN] = IS_OPEN) then doorstate:=DS_LOG_MAG2_NOT_LOCKED; // Magnet 2 did not lock
        end;
       if STATIC_CONFIG[SC_MAGLOCK1] and STATIC_CONFIG[SC_MAGLOCK2] then // Mag 1 and 2
        begin
         if (inputs[MAGLOCK1_RETURN] = IS_CLOSED) and (inputs[MAGLOCK2_RETURN] = IS_CLOSED) then doorstate:=DS_LOG_LOCKED; // Fully locked
         if (inputs[MAGLOCK1_RETURN] = IS_CLOSED) and busy_delay_is_expired (mag2lockwait) then doorstate:=DS_LOG_PARTIAL1; // Partial lock
         if (inputs[MAGLOCK2_RETURN] = IS_CLOSED) and busy_delay_is_expired (mag1lockwait) then doorstate:=DS_LOG_PARTIAL2; // Partial lock
         if busy_delay_is_expired (mag1lockwait) and busy_delay_is_expired (mag2lockwait) then doorstate:=DS_LOG_2MAGS_NOT_LOCKED; // No magnet locked
        end;
       if (not STATIC_CONFIG[SC_MAGLOCK1]) and (not STATIC_CONFIG[SC_MAGLOCK2]) then // No magnet
         doorstate:=DS_LOG_NOMAG;
      end;
     DS_UNLOCKED: // Door unlock order received
      begin
       busy_delay_tick (open_wait, 16); // tick...
       outputs[MAGLOCK1_RELAY]:=false;
       outputs[MAGLOCK2_RELAY]:=false;
       outputs[DOOR_STRIKE_RELAY]:=true;
       if STATIC_CONFIG[SC_BUZZER] then outputs[BUZZER_OUTPUT]:=true;
       if inputs[DOOR_CLOSED_SWITCH] = IS_OPEN then doorstate:=DS_LOG_OPEN;
       if busy_delay_is_expired (open_wait) and (inputs[DOOR_CLOSED_SWITCH] = IS_CLOSED) then
        begin // Door did not open: it stayed closed.
         doorstate:=DS_LOG_CLOSED;
         outputs[BUZZER_OUTPUT]:=false;
        end;
      end;
     DS_LOG_UNLOCK_SYSTEM: // Unlock by system
      begin
       doorstate:=DS_UNLOCKED;
       log_single_door_event (MSG_OPEN_SYSTEM, LOG_ITEM_TEXT_EN, '');
      end;
     DS_LOG_UNLOCK_HANDLE: // Unlock by door handle only
      begin
       doorstate:=DS_UNLOCKED;
       log_single_door_event (MSG_OPEN_HANDLE, LOG_ITEM_TEXT_EN, '');
      end;
     DS_LOG_UNLOCK_HANDLEANDLIGHT: // Unlock by door handle and light on
      begin
       doorstate:=DS_UNLOCKED;
       log_single_door_event (MSG_OPEN_HANDLE_AND_LIGHT, LOG_ITEM_TEXT_EN, '');
      end;
     DS_LOG_UNLOCK_DOORBELL: // Unlock by doorbell (this path is reached in tuesday mode only)
      begin
       doorstate:=DS_UNLOCKED;
       log_single_door_event (MSG_OPEN_DOORBELL, LOG_ITEM_TEXT_EN, '');
      end;
     DS_LOG_PARTIAL1:
      begin
       log_single_door_event (MSG_MAG1PARTIAL, LOG_ITEM_TEXT_EN, '');
       doorstate:=DS_PARTIAL1;
      end;
     DS_PARTIAL1: // Partial lock: magnet 1 catched, but not magnet 2
      begin
       if (inputs[MAGLOCK1_RETURN] = IS_CLOSED) and (inputs[MAGLOCK2_RETURN] = IS_CLOSED) then doorstate:=DS_LOCKED;
       if STATIC_CONFIG[SC_HANDLEANDLIGHT] and (inputs[LIGHTS_ON_SENSE] = IS_CLOSED) and (inputs[DOORHANDLE] = IS_CLOSED) then doorstate:=DS_LOG_UNLOCK_HANDLEANDLIGHT; // Open from handle and light
       if (tuesdaytimer <> 0) and ((inputs[OPTO1] = IS_CLOSED) or (inputs[OPTO2] = IS_CLOSED) or (inputs[OPTO3] = IS_CLOSED))then doorstate:=DS_LOG_UNLOCK_DOORBELL;  // Open from doorbell
      end;
     DS_LOG_PARTIAL2:
      begin
       log_single_door_event (MSG_MAG2PARTIAL, LOG_ITEM_TEXT_EN, '');
       doorstate:=DS_PARTIAL2;
      end;
     DS_PARTIAL2: // Partial lock: magnet 2 catched, but not magnet 1
      begin
       if (inputs[MAGLOCK1_RETURN] = IS_CLOSED) and (inputs[MAGLOCK2_RETURN] = IS_CLOSED) then doorstate:=DS_LOCKED;
       if STATIC_CONFIG[SC_HANDLEANDLIGHT] and (inputs[LIGHTS_ON_SENSE] = IS_CLOSED) and (inputs[DOORHANDLE] = IS_CLOSED) then doorstate:=DS_LOG_UNLOCK_HANDLEANDLIGHT; // Open from handle and light
       if (tuesdaytimer <> 0) and ((inputs[OPTO1] = IS_CLOSED) or (inputs[OPTO2] = IS_CLOSED) or (inputs[OPTO3] = IS_CLOSED))then doorstate:=DS_LOG_UNLOCK_DOORBELL;  // Open from doorbell
      end;
     DS_LOG_2MAGS_NOT_LOCKED:
      begin
       log_single_door_event (MSG_2MAGS_NOLATCH, LOG_ITEM_TEXT_EN, '');
       doorstate:=DS_NOT_LOCKED;
      end;
     DS_LOG_MAG1_NOT_LOCKED:
      begin
       log_single_door_event (MSG_MAG1_NOLATCH, LOG_ITEM_TEXT_EN, '');
       doorstate:=DS_NOT_LOCKED;
      end;
     DS_LOG_MAG2_NOT_LOCKED:
      begin
       log_single_door_event (MSG_MAG2_NOLATCH, LOG_ITEM_TEXT_EN, '');
       doorstate:=DS_NOT_LOCKED;
      end;
     DS_NOT_LOCKED: // Door is not locked !!
      begin
       if STATIC_CONFIG[SC_BUZZER] then outputs[BUZZER_OUTPUT]:=busy_buzzer (buzzertracker, SND_DOORNOTCLOSED, 16);
       if STATIC_CONFIG[SC_MAGLOCK1] and (not STATIC_CONFIG[SC_MAGLOCK2]) and (inputs[MAGLOCK1_RETURN] = IS_CLOSED) then doorstate:=DS_LOG_NOW_LOCKED; // Mag 1 only
       if (not STATIC_CONFIG[SC_MAGLOCK1]) and STATIC_CONFIG[SC_MAGLOCK2] and (inputs[MAGLOCK2_RETURN] = IS_CLOSED) then doorstate:=DS_LOG_NOW_LOCKED; // Mag 2 only
       if STATIC_CONFIG[SC_MAGLOCK1] and STATIC_CONFIG[SC_MAGLOCK2] then // Mag 1 and 2
        begin
{         and (inputs[MAGLOCK1_RETURN] = IS_CLOSED)
         and (inputs[MAGLOCK2_RETURN] = IS_CLOSED)
 }       end;
     end;
     DS_LOG_NOMAG:
      begin
       log_single_door_event (MSG_CLOSED_NOMAG, LOG_ITEM_TEXT_EN, '');
       doorstate:=DS_NOMAG;
      end;
     DS_NOMAG: // No magnet installed (not recommended)
      begin
       if STATIC_CONFIG[SC_HANDLEANDLIGHT] and (inputs[LIGHTS_ON_SENSE] = IS_CLOSED) and (inputs[DOORHANDLE] = IS_CLOSED) then doorstate:=DS_LOG_UNLOCK_HANDLEANDLIGHT; // Open from handle and light
       if (tuesdaytimer <> 0) and ((inputs[OPTO1] = IS_CLOSED) or (inputs[OPTO2] = IS_CLOSED) or (inputs[OPTO3] = IS_CLOSED))then doorstate:=DS_LOG_UNLOCK_DOORBELL;  // Open from doorbell
      end;
     DS_LOG_NOW_LOCKED:
      begin
       log_single_door_event (MSG_NOW_LOCKED, LOG_ITEM_TEXT_EN, '');
       doorstate:=DS_LOCKED;
      end;
     DS_LOG_LOCKED:
      begin
       log_single_door_event (MSG_DOORISLOCKED, LOG_ITEM_TEXT_EN, '');
       doorstate:=DS_LOCKED;
      end;
     DS_LOCKED: // Door is locked
      begin
       if STATIC_CONFIG[SC_BUZZER] then outputs[BUZZER_OUTPUT]:=busy_buzzer (buzzertracker, SND_MISTERCASH, 16);
       if STATIC_CONFIG[SC_HANDLEANDLIGHT] and (inputs[LIGHTS_ON_SENSE] = IS_CLOSED) and (inputs[DOORHANDLE] = IS_CLOSED) then doorstate:=DS_LOG_UNLOCK_HANDLEANDLIGHT; // Open from handle and light
       if (tuesdaytimer <> 0) and ((inputs[OPTO1] = IS_CLOSED) or (inputs[OPTO2] = IS_CLOSED) or (inputs[OPTO3] = IS_CLOSED))then doorstate:=DS_LOG_UNLOCK_DOORBELL;  // Open from doorbell
      end;
     end; // End of door state machine

     // Start of mailbox state machine
     case MailboxSM of
      SM_ENTRY: if STATIC_CONFIG[SC_MAILBOX] then MailboxSM:=SM_ACTIVE;
      SM_ACTIVE: if (inputs[MAILBOX] = IS_CLOSED) then MailboxSM:=SM_LOG_CLOSED else MailboxSM:=SM_OPEN;
      SM_LOG_CLOSED:
       begin
        log_single_door_event (MSG_MAILBOX, LOG_ITEM_TEXT_EN, '');
        MailboxSM:=SM_CLOSED;
       end;
      SM_LOG_OPEN:
       begin
        log_single_door_event (MSG_MAILBOX_THANKS, LOG_ITEM_TEXT_EN, '');
        MailboxSM:=SM_OPEN;
       end;
      SM_CLOSED: if (inputs[MAILBOX] = IS_OPEN) then MailboxSM:=SM_LOG_OPEN;
      SM_OPEN: if (inputs[MAILBOX] = IS_CLOSED) then MailboxSM:=SM_LOG_CLOSED;
     end;
     // End of mailbox state machine

     // Start of tamper switch state machine
     case TamperSM of
      SM_ENTRY: if STATIC_CONFIG[SC_BOX_TAMPER_SWITCH] then TamperSM:=SM_ACTIVE;
      SM_ACTIVE: if (inputs[BOX_TAMPER_SWITCH] = IS_CLOSED) then TamperSM:=SM_CLOSED else TamperSM:=SM_LOG_OPEN;
      SM_LOG_OPEN:
       begin
        log_single_door_event (MSG_BOX_TAMPER, LOG_ITEM_TEXT_EN, '');
        TamperSM:=SM_OPEN;
       end;
      SM_CLOSED: if (inputs[BOX_TAMPER_SWITCH] = IS_OPEN) then TamperSM:=SM_LOG_OPEN;
      SM_OPEN:  if (inputs[BOX_TAMPER_SWITCH] = IS_CLOSED) then TamperSM:=SM_CLOSED;
     end;
     // End of tamper switch state machine

     // Start of tripwire state machine
     case TripwireSM of
      SM_ENTRY: if STATIC_CONFIG[SC_TRIPWIRE_LOOP] then TripwireSM:=SM_ACTIVE;
      SM_ACTIVE: if (inputs[TRIPWIRE_LOOP] = IS_CLOSED) then TripwireSM:=SM_CLOSED else TripwireSM:=SM_LOG_OPEN;
      SM_LOG_OPEN:
       begin
        log_single_door_event (MSG_TRIPWIRE, LOG_ITEM_TEXT_EN, '');
        TripwireSM:=SM_OPEN;
       end;
      SM_CLOSED: if (inputs[TRIPWIRE_LOOP] = IS_OPEN) then TripwireSM:=SM_LOG_OPEN;
      SM_OPEN:  if (inputs[TRIPWIRE_LOOP] = IS_CLOSED) then TripwireSM:=SM_CLOSED;
     end;
     // End of tripwire state machine

//  TSimpleSM=(SM_ENTRY, SM_ACTIVE, SM_LOG_OPEN, SM_OPEN, SM_LOG_REALLY_OPEN, SM_REALLY_OPEN, SM_LOG_CLOSED, SM_CLOSED, SM_LOG_REALLY_CLOSED, SM_REALLY_CLOSED, SM_LOG_STUCK_CLOSED, SM_STUCK_CLOSED, SM_LOG_UNSTUCK);
     // Start of doorbell state machine (stuck closed detection, 50 Hz eater and buzzer-as-a-doorbell)
     // 50 Hz eater: Virtual capacitor concept: full=255; empty=0; charge: cap:=cap+3; discharge: cap:=cap-2;
     case DoorbellSM of
      SM_ENTRY: DoorbellSM:=SM_ACTIVE; // Really ?
      SM_ACTIVE: if (inputs[DOORBELL1] = IS_CLOSED) or (inputs[DOORBELL2] = IS_CLOSED) or (inputs[DOORBELL2] = IS_CLOSED) then DoorbellSM:=SM_LOG_CLOSED;
      SM_LOG_CLOSED:
       begin
        log_single_door_event (MSG_DOORBELL, LOG_ITEM_TEXT_EN, '');
        DoorbellSM:=SM_CLOSED;
       end;
      SM_CLOSED: if (inputs[DOORBELL1] = IS_OPEN) and (inputs[DOORBELL2] = IS_OPEN) and (inputs[DOORBELL2] = IS_OPEN) then DoorbellSM:=SM_ACTIVE;
     end;
     // End of doorbell state machine

     // Start of presence detection state machine, with 50 Hz eater
     case PresenceSM of
      SM_ENTRY: PresenceSM:=SM_ACTIVE; // Really ?
      SM_ACTIVE: if (inputs[LIGHTS_ON_SENSE] = IS_CLOSED) then PresenceSM:=SM_LOG_CLOSED;
      SM_LOG_CLOSED:
       begin
        log_single_door_event (MSG_LIGHT_ON, LOG_ITEM_TEXT_EN, '');
        PresenceSM:=SM_CLOSED;
       end;
      SM_CLOSED: if (inputs[LIGHTS_ON_SENSE] = IS_OPEN) then PresenceSM:=SM_ACTIVE;
     end;
     // End of presence detection state machine

     // Start of doorhandle state machine (stuck closed detection)
     case HandleSM of
      SM_ENTRY: if STATIC_CONFIG[SC_HANDLE] or STATIC_CONFIG[SC_HANDLEANDLIGHT] then HandleSM:=SM_ACTIVE;
      SM_ACTIVE: if (inputs[DOORHANDLE] = IS_CLOSED) then HandleSM:=SM_CLOSED;
      SM_CLOSED:
       begin
        if (inputs[DOORHANDLE] = IS_OPEN) then HandleSM:=SM_ACTIVE; // Handle released
        if ((doorstate=DS_LOCKED) or (doorstate=DS_NOMAG) or (doorstate=DS_PARTIAL1) or (doorstate=DS_PARTIAL2)) and STATIC_CONFIG[SC_HANDLE] then doorstate:=DS_LOG_UNLOCK_HANDLE;
        if STATIC_CONFIG[SC_HANDLEANDLIGHT] then
         if ((doorstate=DS_LOCKED) or (doorstate=DS_NOMAG) or (doorstate=DS_PARTIAL1) or (doorstate=DS_PARTIAL2)) and (PresenceSM=SM_CLOSED) then doorstate:=DS_LOG_UNLOCK_HANDLEANDLIGHT;
        // Stuck closed detection here: tick the timer
       end;
     end;
     // End of doorhandle state machine

     // Start of open button detection state machine (stuck closed detection and 50 Hz eater)
     case OpenButtonSM of
      SM_ENTRY: if STATIC_CONFIG[SC_DOORUNLOCKBUTTON] then OpenButtonSM:=SM_ACTIVE;
      SM_ACTIVE: if (inputs[DOOR_OPEN_BUTTON] = IS_CLOSED) then OpenButtonSM:=SM_CLOSED;
      SM_CLOSED:
       begin
        if (inputs[DOOR_OPEN_BUTTON] = IS_OPEN) then OpenButtonSM:=SM_LOG_OPEN;
        // Stuck closed detection here: tick the timer
       end;
      SM_LOG_OPEN: // Button has been released
       begin
        OpenButtonSM:=SM_ACTIVE;
        if (doorstate=DS_LOCKED) or (doorstate=DS_NOMAG) or (doorstate=DS_PARTIAL1) or (doorstate=DS_PARTIAL2) then // Door was locked, open it.
         begin
          doorstate:=DS_UNLOCKED;
          log_single_door_event (MSG_OPEN_BUTTON, LOG_ITEM_TEXT_EN, '');
         end;
       end;
      SM_LOG_STUCK_CLOSED:
       begin
        log_single_door_event (MSG_DOOROPENBUTTON_STUCK, LOG_ITEM_TEXT_EN, '');
        OpenButtonSM:=SM_STUCK_CLOSED;
       end;
      SM_STUCK_CLOSED:
       begin
        if (inputs[DOOR_OPEN_BUTTON] = IS_OPEN) then OpenButtonSM:=SM_LOG_UNSTUCK;
        // Spam the log on a regular basis to remind something is broken
       end;
      SM_LOG_UNSTUCK: // Button finally released
       begin
        log_single_door_event (MSG_DOOROPENBUTTON_FIXED, LOG_ITEM_TEXT_EN, '');
        OpenButtonSM:=SM_ACTIVE
       end;
     end;
     // End of open button detection state machine

    // Process beep command (independent from state machine flow)
    busy_delay_tick (beepdelay, 16); // tick...
    outputs[BUZZER_OUTPUT]:=(not busy_delay_is_expired (beepdelay)) or outputs[BUZZER_OUTPUT]; // The buzzer might be active elsewhere

(*
      { Corner cases to fix:
        - 'Trigger happy' filtering
        - Stuck closed detection
     }

      log_door_event (msgflags, 31, (busy_delay_is_expired (Mag1CloseWait) and STATIC_CONFIG[SC_MAGLOCK1]),
       'Check maglock 1 and it''s wiring: maglock is off but i see it closed', '');
      log_door_event (msgflags, 32, (busy_delay_is_expired (Mag2CloseWait) and STATIC_CONFIG[SC_MAGLOCK2]),
       'Check maglock 2 and it''s wiring: maglock is off but i see it closed', '');
      log_door_event (msgflags, 33, ((inputs[MAGLOCK1_RETURN] = IS_CLOSED) and not outputs[MAGLOCK1_RELAY] and not STATIC_CONFIG[SC_MAGLOCK1]),
       'Wiring error: maglock 1 is disabled in configuration but i see it closed', '');
      log_door_event (msgflags, 34, ((inputs[MAGLOCK2_RETURN] = IS_CLOSED) and not outputs[MAGLOCK2_RELAY] and not STATIC_CONFIG[SC_MAGLOCK2]),
       'Wiring error: maglock 2 is disabled in configuration but i see it closed', '');
      log_door_event (msgflags, 45, (door_is_locked and (inputs [DOOR_CLOSED_SWITCH] = IS_OPEN)),
       'Check wiring of door switch: door is locked but i see it open', '');
      log_door_event (msgflags, 46, (door_is_locked and outputs[MAGLOCK1_RELAY] and (inputs[MAGLOCK1_RETURN] = IS_OPEN) and STATIC_CONFIG[SC_MAGLOCK1]),
       'Magnetic lock 1 or its wiring failed. Please repair.', '');
      log_door_event (msgflags, 47, (door_is_locked and outputs[MAGLOCK2_RELAY] and (inputs[MAGLOCK2_RETURN] = IS_OPEN) and STATIC_CONFIG[SC_MAGLOCK2]),
       'Magnetic lock 2 or its wiring failed. Please repair.', '');
       *)
(********************************************************************************************************)

{        TSHMVariables=RECORD // What items should be exposed for IPC.
                Inputs, outputs, fakeinputs: TRegisterbits;
                DoorState: TDoorStates;
                TuesdayState: TTuesdaySM;
                MailboxState, TamperState, TripwireState: TSimpleSM;
                state, Config :TLotsofbits;
                senderpid: TPid;
                Command: TCommands;
                SHMMsg:string;
                end;
 }
    if dryrun = 0 then // Make a dry run to let inputs settle
     begin
      SHMPointer^.inputs:=inputs;
      SHMPointer^.outputs:=outputs;
      SHMPointer^.DoorState:=doorstate;
      SHMPointer^.MailboxState:=MailboxSM;
      SHMPointer^.state:=CurrentState;
      SHMPointer^.Config:=STATIC_CONFIG;
     end;
   until CurrentState[S_STOP];
  end;
 log_single_door_event (MSG_BAILOUT, LOG_ITEM_TEXT_EN, '');
 outputs:=word2bits (0);
 if not CurrentState[S_DEMOMODE] then ls673_write (@setregclock, @setregdata, @setregstrobe,  outputs);
 sleep (100); // Give time for the monitor to die before yanking the segment
 shmctl (shmid, IPC_RMID, nil); // Destroy shared memory segment upon leaving
 GpIo_Driver.destroy;
end;

// Do something on signal
procedure signalhandler (sig: longint); cdecl;
begin
 case sig of
  SIGHUP: CurrentState[S_HUP]:=true;
  SIGTERM: CurrentState[S_STOP]:=true;
 end;
end;

// Collect and dispose of the dead bodies
procedure children_of_bodom (sig: longint); cdecl;
var childexitcode: cint;
begin
 syslog (log_info, 'Grim reaper: child %d exited with code: %d', [ FpWait (childexitcode), childexitcode]);
end;

// For IPC stuff (sending commands)
Procedure senddaemoncommand (daemonpid: TPid; cmd: TCommands; comment: string);
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
   SHMPointer^.senderpid:=FpGetPid;
   SHMPointer^.command:=cmd;
   if comment = '' then SHMPointer^.SHMMsg:='<no message provided>'
                   else SHMPointer^.SHMMsg:=comment;
   fpkill (daemonpid, SIGHUP);
  end;
end;


///////////// MAIN BLOCK /////////////
var     shmname, pidname :string;
        aOld, aTerm, aHup, aChild : pSigActionRec;
        zerosigs : sigset_t;
        ps1 : psigset;
        sSet : cardinal;
        oldpid, sid, pid: TPid;
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
  'shell':     debug_shell;
  'running':   if iamrunning then halt (0) else halt (1);
  'stop':      if iamrunning then fpkill (oldpid, SIGTERM);
  'beep':      senddaemoncommand (oldpid, CMD_BEEP, paramstr (2));
  'tuesday':   senddaemoncommand (oldpid, CMD_TUESDAY_START, paramstr (2));
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
       sSet := $fffebffe;
       ps1 := @sSet;
       fpsigprocmask(sig_block,ps1,nil);
       { setup the signal handlers }
       new(aOld);
       new(aHup);
       new(aTerm);
       new(aChild);
       aTerm^.sa_handler := SigactionHandler(@signalhandler);
       aTerm^.sa_mask := zerosigs;
       aTerm^.sa_flags := 0;
       aTerm^.sa_restorer := nil;
       aHup^.sa_handler := SigactionHandler(@signalhandler);
       aHup^.sa_mask := zerosigs;
       aHup^.sa_flags := 0;
       aHup^.sa_restorer := nil;
       aChild^.sa_handler := SigactionHandler(@children_of_bodom);
       aChild^.sa_mask := zerosigs;
       aChild^.sa_flags := 0;
       aChild^.sa_restorer := nil;
       fpSigAction(SIGTERM,aTerm,aOld);
       fpSigAction(SIGHUP,aHup,aOld);
       fpSigAction(SIGCHLD,aChild,aOld);

       pid := fpFork;
       if pid = 0 then
        Begin // we're in the child
         openlog (pchar (format (ApplicationName + '[%d]', [fpgetpid])), LOG_NOWAIT, LOG_DAEMON);
         syslog (log_info, 'Spawned new process: %d. Build date/time: %s'#10, [fpgetpid, {$I %DATE%} + ' ' + {$I %TIME%}]);
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
