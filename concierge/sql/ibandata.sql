--
--	Concierge for Hackerspace Brussels - IBAN data
--	Taken from http://en.wikipedia.org/wiki/International_Bank_Account_Number
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

-- Since we're coming with fresh data, don't hesitate to delete the whole table
-- It will be re-filled with fresh data
TRUNCATE TABLE validiban;

INSERT INTO validiban (country, validlength) VALUES ('AL', 28),
			('AD', 24),('AT', 20),('AZ', 28),('BH', 22),('BE', 16),('BA', 20),
			('BR', 29),('BG', 22),('CR', 21),('HR', 21),('CY', 28),('CZ', 24),
			('DK', 18),('DO', 28),('EE', 20),('FO', 18),('FI', 18),('FR', 27),
			('GE', 22),('DE', 22),('GI', 23),('GR', 27),('GL', 18),('GT', 28),
			('HU', 28),('IS', 26),('IE', 22),('IL', 23),('IT', 27),('KZ', 20),
			('KW', 30),('LV', 21),('LB', 28),('LI', 21),('LT', 20),('LU', 20),
			('MK', 19),('MT', 31),('MR', 27),('MU', 30),('MC', 27),('MD', 24),
			('ME', 22),('NL', 18),('NO', 15),('PK', 24),('PS', 29),('PL', 28),
			('PT', 25),('RO', 24),('SM', 27),('SA', 24),('RS', 22),('SK', 24),
			('SI', 19),('ES', 24),('SE', 24),('CH', 21),('TN', 24),('TR', 26),
			('AE', 23),('GB', 22),('VG', 24);
