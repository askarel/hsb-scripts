--
--	Concierge for Hackerspace Brussels - triggers definition
--
--	(c) 2014 Frederic Pasteleurs <frederic@askarel.be>
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

DROP TRIGGER if exists log_person_activity_update;;
CREATE TRIGGER log_person_activity_update AFTER UPDATE ON person FOR EACH ROW
    begin
	if new.machinestate <> old.machinestate or new.machinestate_data <> old.machinestate_data or new.machinestate_expiration_date <> old.machinestate_expiration_date then
	    INSERT INTO person_history (event_timestamp, member_id, machinestate, machinestate_data, machinestate_expiration_date) VALUES (NOW(), old.id, new.machinestate, new.machinestate_data, new.machinestate_expiration_date);
	end if;
    end;;

DROP TRIGGER if exists log_person_activity_insert;;
CREATE TRIGGER log_person_activity_insert AFTER INSERT ON person FOR EACH ROW
	INSERT INTO person_history (event_timestamp, member_id, machinestate, machinestate_data, machinestate_expiration_date) VALUES (NOW(), new.id, new.machinestate, new.machinestate_data, new.machinestate_expiration_date);;

DROP TRIGGER if exists person_auto_entry_date;;
create trigger person_auto_entry_date before insert on person for each row 
    begin
	if new.nickname = '' or new.nickname = NULL then
	    set new.nickname=replace (concat (new.firstname, '_',new.name), ' ', '_'); -- Craft an unlikely nickname :-)
	end if;
	if new.structuredcomm = '' or new.structuredcomm = NULL then
	    set new.structuredcomm=(select formatbecomm((select ifnull (max(id), 0) + 1 from person)));
	end if;
    end;;

DELIMITER ;
