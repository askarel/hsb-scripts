--
--	Concierge for Hackerspace Brussels - stored functions definitions
--
--	(c) 2013 Frederic Pasteleurs <frederic@askarel.be>
--
--    This program is free software: you can redistribute it and/or modify
--    it under the terms of the GNU General Public License as published by
--    the Free Software Foundation, either version 3 of the License, or
--    (at your option) any later version.
--
--    This program is distributed in the hope that it will be useful,
--    but WITHOUT ANY WARRANTY; without even the implied warranty of
--    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--    GNU General Public License for more details.
--
--    You should have received a copy of the GNU General Public License
--    along with this program.  If not, see <http://www.gnu.org/licenses/>.
--
DELIMITER ;;

-- Randomly generated belgian-style structured communication
DROP FUNCTION IF EXISTS mkbecomm;;
CREATE FUNCTION `mkbecomm`() RETURNS char(20) CHARSET latin1
begin
set @commbase:=lpad (floor (1 + (rand() * 9999999999 )),10, '0');
return (select concat ('+++', insert (insert (@commbase, 8, 0, '/'), 4, 0, '/'), lpad ((case mod (@commbase, 97) when 0 then 97 else (mod (@commbase, 97))end),2,'0'), '+++'));
end ;;

-- Format any number between 0 and 9999999999 into a belgian style structured communication
DROP FUNCTION IF EXISTS formatbecomm;;
CREATE FUNCTION formatbecomm (commnumber BIGINT) RETURNS char(20)
begin
 DECLARE commbase char(10);
 DECLARE commmod char (2);
 SET commbase:=lpad (commnumber, 10, '0');
 SET commmod:=lpad (( case mod (commbase, 97) when 0 then 97 else (mod (commbase, 97)) end), 2, '0');
 RETURN (select concat ('+++', insert (insert( commbase, 8, 0, '/'), 4, 0, '/'), commmod , '+++'));
end ;;

-- Provision empty accounts
DROP PROCEDURE IF EXISTS intacc_provision;;
create procedure intacc_provision (commqty INT)
begin
 DECLARE x int default 0;
 while x <= commqty do 
  insert into internal_accounts (structuredcomm) values ( mkbecomm());
  set x = x + 1;
 end while;
end;;

-- Create the internal account
-- Return account ID in case of success
DROP procedure IF EXISTS intacc_create;;
create procedure intacc_create (ACCNTTYPE char(20), OWNER_DN char(255), REF_DN char(255))
begin
 DECLARE INTERNALACCOUNT char(20);
 set INTERNALACCOUNT:=(select structuredcomm from internal_accounts where account_type is null limit 1);
 if INTERNALACCOUNT is NULL
    then 
	signal SQLSTATE '45000'	SET MESSAGE_TEXT = 'No spare accound IDs found! Run intacc_provision() first!';
    else
	update internal_accounts set in_use=1, account_type=ACCNTTYPE, owner_dn=OWNER_DN, created_on=CURRENT_TIMESTAMP, ref_dn=REF_DN where structuredcomm like INTERNALACCOUNT;
	select INTERNALACCOUNT;
 END IF;
end;;

-- Preload an amount on the internal account
DROP PROCEDURE IF EXISTS intacc_preload;;
create procedure intacc_preload (accid char(20), POSID char(50), AMOUNT decimal(15,4), CURRENCY char(5), Message char(255))
begin
 DECLARE TRANS_ID char(255);
 DECLARE INTERNALACCOUNT char(20);
 set INTERNALACCOUNT:=(select structuredcomm from internal_accounts where structuredcomm like accid and in_use=1);
 if INTERNALACCOUNT is NULL
    then 
	signal SQLSTATE '45001'	SET MESSAGE_TEXT = 'Specified internal account ID does not exist.';
    else
	SET TRANS_ID:=concat ('INTERNAL/', accid, '/', POSID, '/', sha1(concat (current_timestamp(), Message)) );
	insert into moneymovements (date_val, date_account, amount, currency, other_account, this_account, message, transaction_id) VALUES 
                        	    (curdate(), curdate(), concat ('-', abs (AMOUNT)), CURRENCY, POSID, accid, Message, TRANS_ID);
 END IF;
end;;

-- Consume an internal account
DROP PROCEDURE IF EXISTS intacc_consume;;
create procedure intacc_consume (accid char(20), POSID char(50), AMOUNT2PAY decimal(15,4), CURRENCY char(5), MSG char(255))
begin
 DECLARE TRANS_ID char(255);
 DECLARE INTERNALACCOUNT char(20);
 DECLARE BALANCE decimal(15,4);
 set INTERNALACCOUNT:=(select structuredcomm from internal_accounts where structuredcomm like accid and in_use=1);
 set BALANCE:=(select sum(amount) from moneymovements where this_account like INTERNALACCOUNT);
 if BALANCE is null 
	then set BALANCE:=0; 
 end if;
 if INTERNALACCOUNT is NULL
    then 
	signal SQLSTATE '45001'	SET MESSAGE_TEXT = 'Specified internal account ID does not exist.';
    else
    if (AMOUNT2PAY + BALANCE) > 0
	then 
	    signal SQLSTATE '45002'	SET MESSAGE_TEXT = 'Cannot pay: not enough money on account.';
	else
	    SET TRANS_ID:=concat ('INTERNAL/', accid, '/', POSID, '/', sha1(concat (current_timestamp(), MSG)) );
	    insert into moneymovements (date_val, date_account, amount, currency, other_account, this_account, message, transaction_id) VALUES 
                        		(curdate(), curdate(), abs (AMOUNT2PAY), CURRENCY, POSID, accid, MSG, TRANS_ID);
	end if;
 END IF;
end;;

-- Get balance of specified account
DROP PROCEDURE IF EXISTS intacc_get_balance;;
create procedure intacc_get_balance (accid char(20))
begin
 DECLARE INTERNALACCOUNT char(20);
 set INTERNALACCOUNT:=(select structuredcomm from internal_accounts where structuredcomm like accid and in_use=1);
 if INTERNALACCOUNT is NULL
    then 
	signal SQLSTATE '45001'	SET MESSAGE_TEXT = 'Specified internal account ID does not exist.';
    else
	select abs(sum(amount)), currency from moneymovements where this_account like INTERNALACCOUNT;
 END IF;
end;;

-- Transfer between internal accounts
DROP PROCEDURE IF EXISTS intacc_transfer;;


DELIMITER ;
