program de_lift;
{
 De Lift - handler for the elevator hardware

 (c) 2016 Frederic Pasteleurs <frederic@askarel.be>

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

 This is a gutted down version of the black knight.
}
uses PiGpio, unix, sysutils, ipc, systemlog, baseunix, pidfile, typinfo;

CONST   SHITBITS=16; // Should go away at some point

TYPE    TLotsofbits=bitpacked array [0..SHITBITS] of boolean; // A shitload of bits to abuse. 64 bits should be enough. :-) Should go away at some point.

        // Available error messages
        TLogItems=(MSG_DEMO, MSG_BOX_TAMPER, MSG_BUTTON_PUSHED, MSG_LONG_BUTTON_PUSH, MSG_BUTTON_STUCK, MSG_BUTTON_FIXED, MSG_TUESDAY_INACTIVE,
                MSG_TUESDAY_ACTIVE_CMDLINE, MSG_TUESDAY_ACTIVE_TAG, MSG_TUESDAY_TIMEOUT, MSG_TUESDAY_IS_ACTIVE, MSG_TUESDAY_IS_INACTIVE, MSG_TUESDAY_FORCE_INACTIVE,
                MSG_TUESDAY_CALL, MSG_BOX_RECLOSED, MSG_SPARE1_CLOSED, MSG_SPARE1_OPEN, MSG_SPARE2_CLOSED, MSG_SPARE2_OPEN, MSG_ELEVATOR_CMDLINE, MSG_BAILOUT);
       TCommands=(CMD_NONE, CMD_GOHOME, CMD_TUESDAY_START, CMD_QUERYTUESDAY, CMD_TUESDAY_STOP, CMD_STOP);
       TLogItemText= ARRAY[TLogItems] of pchar;
        // Tuesday mode state machine
        TTuesdaySM=(SM_OFF, SM_LOG_START_CMDLINE, SM_LOG_START_VALID_TAG, SM_START, SM_TICK, SM_LOG_STOP_CMDLINE, SM_LOG_STOP_TIMEOUT, SM_LOG_STOP_BUTTON);
        // Simple universal state machine definition (let's see how far it flies)
        TSimpleSM=(SM_ENTRY, SM_ACTIVE, SM_LOG_OPEN, SM_OPEN, SM_LOG_REALLY_OPEN, SM_REALLY_OPEN, SM_LOG_CLOSED, SM_CLOSED, SM_LOG_REALLY_CLOSED,
                   SM_REALLY_CLOSED, SM_LOG_STUCK_CLOSED, SM_STUCK_CLOSED, SM_LOG_UNSTUCK);
        TElevatorSM=(EL_ENTRY, EL_LOG_CALL, EL_CALL_SET, EL_CALL_RESET, EL_TICK);

        TSHMVariables=RECORD // What items should be exposed for IPC.
                TuesdayState: TTuesdaySM;
                ElevatorState: TElevatorSM;
                TamperState, ButtonState, Spare1State, Spare2State: TSimpleSM;
                state, SimulState :TLotsofbits;
                senderpid: TPid;
                Command: TCommands;
                SHMMsg:string;
                end;

CONST
        CMD_NAME: ARRAY [TCommands] of pchar=('NoCMD','goto_floor','tuesday_start', 'query_tuesday','tuesday_end','stop');
        LOG_ITEM_TEXT_EN: TLogItemText=('WARNING: Error mapping registry: GPIO code disabled, running in demo mode.',
                                        'WARNING: the box is being tampered !',
                                        'Button has been pushed',
                                        'Long push on button',
                                        'Button is stuck. Please repair.',
                                        'Button has been fixed. Thanks.',
                                        'Tuesday mode inactive',
                                        'Tuesday mode activated by command line. Push lit button to go to 4th floor',
                                        'Tuesday mode activated by valid tag. I''m taking you to the 4th floor',
                                        'Tuesday mode timeout',
                                        'Tuesday mode is active',
                                        'Tuesday mode is inactive',
                                        'Tuesday mode forcefully de-activated by button',
                                        'Tuesday mode: elevator called by button',
                                        'Controller box has been re-closed',
                                        'Unknown input closed (SPARE1)',
                                        'Unknown input opened (SPARE1)',
                                        'Unknown input closed (SPARE2)',
                                        'Unknown input opened (SPARE2)',
                                        'Elevator called from commandline',
                                        'Controller is bailing out !' );

//        TUESDAY_DEFAULT_TIME=1000*60*60*3; // tuesday timer: 3 hours
        TUESDAY_DEFAULT_TIME=1000*60*6; // tuesday timer: 6 minutes (debug)
        CALL_DELAY=100; // 100 mS to trigger the 555
        LONG_PUSH_DELAY=10*1000; // Long push on button (10 seconds)
        STUCK_DELAY=3*60*1000; // Delay to determine being stuck (3 minutes)
        S_DEMOMODE=0; S_STOP=1; S_HUP=2; S_I_BUTTON=3; S_I_TAMPER=4; S_I_SPARE1=5; S_I_SPARE2=6; S_O_CALL=7; S_O_LED=8; S_BLOCK=9;
        IS_CLOSED=false;
        IS_OPEN=true;
 // Convert Raspberry Pi P1 pins (Px) to GPIO port
     P3 = 0;
     P5 = 1;
     P7 = 4;
     P8 = 14;
     P10 = 15;
     P11 = 17;
     P12 = 18;
     P13 = 21;
     P15 = 22;
     P16 = 23;
     P18 = 24;
     P19 = 10;
     P21 = 9;
     P22 = 25;
     P23 = 11;
     P24 = 8;
     P26 = 7;
         PIN_O_ELEVATOR_CALL=P26;
         PIN_O_BUTTON_LED=P18;
         PIN_I_BUTTON=P16;
         PIN_I_TAMPER_SW=P8;
         PIN_I_SPARE1=P12;
         PIN_I_SPARE2=P10;


VAR     GPIO_Driver: TIODriver;
        GpF: TIOPort;
        CurrentState: TLotsOfBits;   // Reason for global: it is modified by the signal handler

///////////// COMMON LIBRARY FUNCTIONS /////////////

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

// Return true if the GPIO pins have been successfully initialized
function initgpios: boolean;
begin
 Gpio_Driver:=TIODriver.create;
 if GPIO_Driver.MapIo then
  begin
   GpF := GpIo_Driver.CreatePort(GPIO_BASE, CLOCK_BASE, GPIO_PWM);
   GpF.SetPinMode (PIN_O_ELEVATOR_CALL, pigpio.OUTPUT);
   GpF.setpinmode (PIN_O_BUTTON_LED, pigpio.OUTPUT);
   GpF.setpinmode (PIN_I_BUTTON, pigpio.INPUT);
   GpF.setpinmode (PIN_I_TAMPER_SW, pigpio.INPUT);
   GpF.setpinmode (PIN_I_SPARE1, pigpio.INPUT);
   GpF.setpinmode (PIN_I_SPARE2, pigpio.INPUT);
   GpF.setpullmode (PIN_I_BUTTON, pigpio.PUD_Up);
   GpF.setpullmode (PIN_I_TAMPER_SW, pigpio.PUD_Up);
   GpF.setpullmode (PIN_I_SPARE1, pigpio.PUD_Up);
   GpF.setpullmode (PIN_I_SPARE2, pigpio.PUD_Up);
   initgpios:=true;
  end
  else
   initgpios:=false;
end;

procedure godaemon (daemonpid: Tpid);
var shmname: string;
    shmkey: TKey;
    shmid: longint;
    SHMPointer: ^TSHMVariables;
    tuesdaystate: TTuesdaySM;
    TamperSM, ButtonSM, Spare1SM, Spare2SM: TSimpleSM;
    ElevatorSM: TElevatorSM;
    tuesdaytimer, ElevatorTimer, BtnStuckTimer, BtnLongTimer: longint;
begin
 TamperSM:=SM_ENTRY; Spare1SM:=SM_ENTRY; Spare2SM:=SM_ENTRY; tuesdaystate:=SM_OFF; ButtonSM:=SM_ENTRY; ElevatorSM:=EL_ENTRY; // Initialize the state machines
 fillchar (CurrentState, sizeof (CurrentState), 0);
 shmname:=paramstr (0) + #0;
 shmkey:=ftok (pchar (@shmname[1]), daemonpid);
 shmid:=shmget (shmkey, sizeof (TSHMVariables), IPC_CREAT or IPC_EXCL or 438);
 if shmid = -1 then syslog (log_err, 'Can''t create shared memory segment (pid %d). Leaving.', [daemonpid])
 else
  begin // start from a clean state
   SHMPointer:=shmat (shmid, nil, 0);
   fillchar (SHMPointer^, sizeof (TSHMVariables), 0);
   if initgpios then
    CurrentState[S_DEMOMODE]:=false
   else
    begin
     log_single_door_event (MSG_DEMO, LOG_ITEM_TEXT_EN, '');
     CurrentState[S_DEMOMODE]:=true;
    end;

   repeat
    sleep (1);
    if CurrentState[S_DEMOMODE] then // I/O cycle
     begin // Fake I/O
     end
     else // Real I/O
      begin
       CurrentState[S_I_TAMPER]:=GpF.GetBit (PIN_I_TAMPER_SW);
       CurrentState[S_I_BUTTON]:=GpF.GetBit (PIN_I_BUTTON);
       CurrentState[S_I_SPARE1]:=GpF.GetBit (PIN_I_SPARE1);
       CurrentState[S_I_SPARE2]:=GpF.GetBit (PIN_I_SPARE2);
       if CurrentState[S_O_CALL] then GpF.SetBit (PIN_O_ELEVATOR_CALL) else Gpf.ClearBit (PIN_O_ELEVATOR_CALL);
       if CurrentState[S_O_LED] then GpF.SetBit (PIN_O_BUTTON_LED) else Gpf.ClearBit (PIN_O_BUTTON_LED);
      end;
    if CurrentState[S_HUP] then // Process HUP signal
     begin
      SHMPointer^.shmmsg:=SHMPointer^.shmmsg + #0; // Make sure the string is null terminated
      syslog (log_info, 'HUP received from PID %d. Command: "%s" with parameter: "%s"', [ SHMPointer^.senderpid, CMD_NAME[SHMPointer^.command], @SHMPointer^.shmmsg[1]]);
      case SHMPointer^.command of
       CMD_STOP: CurrentState[S_STOP]:=true;
       CMD_GOHOME: if (ButtonSM=SM_CLOSED) or (ButtonSM=SM_REALLY_CLOSED) then
                    begin
                     tuesdaystate:=SM_LOG_START_VALID_TAG;
                     if (ElevatorSM=EL_CALL_RESET) then ElevatorSM:=EL_CALL_SET;
                     CurrentState[S_BLOCK]:=true;
                    end
                    else
                     if (ElevatorSM=EL_CALL_RESET) then ElevatorSM:=EL_LOG_CALL;
       CMD_TUESDAY_START: tuesdaystate:=SM_LOG_START_CMDLINE; // Start tuesday timer
       CMD_QUERYTUESDAY: if TuesdayState=SM_OFF
                                then log_single_door_event (MSG_TUESDAY_IS_INACTIVE, LOG_ITEM_TEXT_EN, '')
                                else log_single_door_event (MSG_TUESDAY_IS_ACTIVE, LOG_ITEM_TEXT_EN, '');
       CMD_TUESDAY_STOP: tuesdaystate:=SM_LOG_STOP_CMDLINE; // Early stop of the tuesday mode
      end;
      SHMPointer^.command:=CMD_NONE;
      CurrentState[S_HUP]:=false; // Reset HUP signal
      SHMPointer^.senderpid:=0; // Reset sender PID: If zero, we may have a race condition
     end;

    // Start of tuesday mode state machine
    case tuesdaystate of
     SM_OFF:
      begin
       tuesdaytimer:=0; // Tuesday mode is off
       CurrentState[S_O_LED]:=false;
      end;
     SM_LOG_START_CMDLINE: // Start the tuesday timer (cmdline)
      begin
       log_single_door_event (MSG_TUESDAY_ACTIVE_CMDLINE, LOG_ITEM_TEXT_EN, '');
       tuesdaystate:=SM_START;
      end;
     SM_LOG_START_VALID_TAG: // Start the tuesday timer (with valid tag) and call elevator
      begin
       log_single_door_event (MSG_TUESDAY_ACTIVE_TAG, LOG_ITEM_TEXT_EN, pchar (@SHMPointer^.shmmsg[1]));
       tuesdaystate:=SM_START;
      end;
     SM_START:
      begin
       tuesdaytimer:=TUESDAY_DEFAULT_TIME;
       CurrentState[S_O_LED]:=true;
       tuesdaystate:=SM_TICK;
      end;
     SM_TICK: //Tick the tuesday timer
      begin
       if tuesdaytimer=0 then tuesdaystate:=SM_LOG_STOP_TIMEOUT;
       busy_delay_tick (tuesdaytimer, 1);
      end;
     SM_LOG_STOP_CMDLINE: // stop the timer (cmdline)
      begin
       log_single_door_event (MSG_TUESDAY_INACTIVE, LOG_ITEM_TEXT_EN, '');
       tuesdaystate:=SM_OFF;
      end;
     SM_LOG_STOP_TIMEOUT: // stop the timer (timeout)
      begin
       log_single_door_event (MSG_TUESDAY_TIMEOUT, LOG_ITEM_TEXT_EN, '');
       tuesdaystate:=SM_OFF;
      end;
     SM_LOG_STOP_BUTTON: // stop the timer (via button)
      begin
       log_single_door_event (MSG_TUESDAY_FORCE_INACTIVE, LOG_ITEM_TEXT_EN, '');
       tuesdaystate:=SM_OFF;
      end;
    end;
    // End of tuesday mode state machine

     // Start of tamper switch state machine
     case TamperSM of
      SM_ENTRY: TamperSM:=SM_ACTIVE;
      SM_ACTIVE: if (CurrentState[S_I_TAMPER] = IS_CLOSED) then TamperSM:=SM_CLOSED else TamperSM:=SM_LOG_OPEN;
      SM_LOG_OPEN:
       begin
        log_single_door_event (MSG_BOX_TAMPER, LOG_ITEM_TEXT_EN, '');
        TamperSM:=SM_OPEN;
       end;
      SM_CLOSED: if (CurrentState[S_I_TAMPER] = IS_OPEN) then TamperSM:=SM_LOG_OPEN;
      SM_LOG_CLOSED:
       begin
        log_single_door_event (MSG_BOX_RECLOSED, LOG_ITEM_TEXT_EN, '');
        TamperSM:=SM_CLOSED;
       end;
      SM_OPEN:  if (CurrentState[S_I_TAMPER] = IS_CLOSED) then TamperSM:=SM_LOG_CLOSED;
     end;
     // End of tamper switch state machine

     // Start of Spare1 switch state machine
     case Spare1SM of
      SM_ENTRY: Spare1SM:=SM_ACTIVE;
      SM_ACTIVE: if (CurrentState[S_I_SPARE1] = IS_CLOSED) then Spare1SM:=SM_CLOSED else Spare1SM:=SM_OPEN;
      SM_LOG_OPEN:
       begin
        log_single_door_event (MSG_SPARE1_OPEN, LOG_ITEM_TEXT_EN, '');
        Spare1SM:=SM_OPEN;
       end;
      SM_CLOSED: if (CurrentState[S_I_SPARE1] = IS_OPEN) then Spare1SM:=SM_LOG_OPEN;
      SM_LOG_CLOSED:
       begin
        log_single_door_event (MSG_SPARE1_CLOSED, LOG_ITEM_TEXT_EN, '');
        Spare1SM:=SM_CLOSED;
       end;
      SM_OPEN:  if (CurrentState[S_I_SPARE1] = IS_CLOSED) then Spare1SM:=SM_LOG_CLOSED;
     end;
     // End of Spare1 switch state machine

     // Start of Spare2 switch state machine
     case Spare2SM of
      SM_ENTRY: Spare2SM:=SM_ACTIVE;
      SM_ACTIVE: if (CurrentState[S_I_SPARE2] = IS_CLOSED) then Spare2SM:=SM_CLOSED else Spare2SM:=SM_OPEN;
      SM_LOG_OPEN:
       begin
        log_single_door_event (MSG_SPARE2_OPEN, LOG_ITEM_TEXT_EN, '');
        Spare2SM:=SM_OPEN;
       end;
      SM_CLOSED: if (CurrentState[S_I_SPARE2] = IS_OPEN) then Spare2SM:=SM_LOG_OPEN;
      SM_LOG_CLOSED:
       begin
        log_single_door_event (MSG_SPARE2_CLOSED, LOG_ITEM_TEXT_EN, '');
        Spare2SM:=SM_CLOSED;
       end;
      SM_OPEN:  if (CurrentState[S_I_SPARE2] = IS_CLOSED) then Spare2SM:=SM_LOG_CLOSED;
     end;
     // End of Spare2 switch state machine

     // Start of button state machine (with stuck closed detection)
     case ButtonSM of
      SM_ENTRY: ButtonSM:=SM_ACTIVE;
      SM_ACTIVE: if (CurrentState[S_I_BUTTON] = IS_CLOSED) then
       begin
        ButtonSM:=SM_CLOSED;
        BtnStuckTimer:=STUCK_DELAY;
        BtnLongTimer:=LONG_PUSH_DELAY;
        CurrentState[S_BLOCK]:=false;
       end;
      SM_CLOSED:
       begin
        if (CurrentState[S_I_BUTTON] = IS_OPEN) then ButtonSM:=SM_LOG_OPEN;
        busy_delay_tick (BtnLongTimer, 1);
        if (BtnLongTimer=0) then ButtonSM:=SM_LOG_REALLY_CLOSED;
       end;
      SM_LOG_REALLY_CLOSED:
       begin
        ButtonSM:=SM_REALLY_CLOSED;
       end;
      SM_REALLY_CLOSED:
       begin
        busy_delay_tick (BtnStuckTimer, 1);
        if BtnStuckTimer=0 then ButtonSM:=SM_LOG_STUCK_CLOSED;
        if (CurrentState[S_I_BUTTON] = IS_OPEN) then ButtonSM:=SM_LOG_REALLY_OPEN;
        if (tuesdaystate=SM_TICK) then tuesdaystate:=SM_LOG_STOP_BUTTON;    // !! BUG ?
       end;
      SM_LOG_OPEN: // Button has been released
       begin
        ButtonSM:=SM_ACTIVE;
         if (tuesdayState=SM_TICK) then
          begin // In tuesday mode
           if not CurrentState[S_BLOCK] then log_single_door_event (MSG_TUESDAY_CALL, LOG_ITEM_TEXT_EN, '');
           ElevatorSM:=EL_CALL_SET;
          end
          else  // Outside tuesday mode
           log_single_door_event (MSG_BUTTON_PUSHED, LOG_ITEM_TEXT_EN, '');
       end;
      SM_LOG_REALLY_OPEN:
       begin
        ButtonSM:=SM_REALLY_OPEN;
       end;
      SM_REALLY_OPEN:
       ButtonSM:=SM_ACTIVE;
      SM_LOG_STUCK_CLOSED:
       begin
        log_single_door_event (MSG_BUTTON_STUCK, LOG_ITEM_TEXT_EN, '');
        ButtonSM:=SM_STUCK_CLOSED;
       end;
      SM_STUCK_CLOSED:
       begin
        if (CurrentState[S_I_BUTTON] = IS_OPEN) then ButtonSM:=SM_LOG_UNSTUCK;
        // TODO: Spam the log on a regular basis to remind something is broken
       end;
      SM_LOG_UNSTUCK: // Button finally released
       begin
        log_single_door_event (MSG_BUTTON_FIXED, LOG_ITEM_TEXT_EN, '');
        ButtonSM:=SM_ACTIVE
       end;
     end;
     // End of button state machine

     // Start of elevator state machine
     case ElevatorSM of
      EL_ENTRY:ElevatorSM:=EL_CALL_RESET;
      EL_CALL_RESET: CurrentState[S_O_CALL]:=false;
      EL_LOG_CALL:
       begin
        log_single_door_event (MSG_ELEVATOR_CMDLINE, LOG_ITEM_TEXT_EN, pchar (@SHMPointer^.shmmsg[1]));
        ElevatorSM:=EL_CALL_SET;
       end;
      EL_CALL_SET:
       begin
        CurrentState[S_O_CALL]:=true;
        ElevatorTimer:=CALL_DELAY;
        ElevatorSM:=EL_TICK;
       end;
      EL_TICK:
       begin
        busy_delay_tick (ElevatorTimer, 1);
        if ElevatorTimer=0 then ElevatorSM:=EL_CALL_RESET;
       end;
      end;
     // End of elevator state machine

      SHMPointer^.TuesdayState:=tuesdaystate;
      SHMPointer^.TamperState:=TamperSM;
      SHMPointer^.ElevatorState:=ElevatorSM;
      SHMPointer^.ButtonState:=ButtonSM;
      SHMPointer^.Spare1State:=Spare1SM;
      SHMPointer^.Spare2State:=Spare2SM;
      SHMPointer^.state:=CurrentState; // Should go away
   until CurrentState[S_STOP];
  end;
 log_single_door_event (MSG_BAILOUT, LOG_ITEM_TEXT_EN, '');
 sleep (100); // Give time for the monitor to die before yanking the segment
 shmctl (shmid, IPC_RMID, nil); // Destroy shared memory segment upon leaving
 GpIo_Driver.destroy;
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
  'running':   if iamrunning then halt (0) else halt (1);
  'stop':      if iamrunning then fpkill (oldpid, SIGTERM);
  'tuesday':   senddaemoncommand (oldpid, CMD_TUESDAY_START, paramstr (2));
  'endtuesday':senddaemoncommand (oldpid, CMD_TUESDAY_STOP, paramstr (2));
  'gohome':    senddaemoncommand (oldpid, CMD_GOHOME, '(cmdline): ' + paramstr (2));
  'querytuesday': senddaemoncommand (oldpid, CMD_QUERYTUESDAY, paramstr (2));
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
  else
   begin
    writeln ('This is the main control program for De Lift, HSBXL elevator controller.');
    if (paramstr (1) <> '') and (lowercase (paramstr (1)) <> 'help') then writeln ('ERROR: unknown parameter: ''', paramstr (1),'''.');
    writeln;
    writeln ('Usage: ', applicationname, ' [start|stop|tuesday|endtuesday|gohome|running] [...]');
    writeln;
    writeln ('Command line parameters:');
    writeln ('  start      - Start the daemon');
    writeln ('  stop       - Stop the daemon');
    writeln ('  tuesday    - Start open mode');
    writeln ('  querytuesday - For script usage: Check if tuesday mode is active');
    writeln ('  endtuesday - End open mode');
    writeln ('  gohome     - Send the elevator to our destination. Any extra parameter is logged to syslog as extra text');
    writeln ('  running    - For script usage: tell if the main daemon is running (check exitcode: 0=running 1=not running)');
    halt (1);
   end;
 end;
end.
