--
--	Concierge for Hackerspace Brussels - tables definition
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

-- New object - describe a person related to the hackerspace.
-- This allow us to describe a person that is not a member, but is related to the hackerspace.
-- It can be the neighbour(s), the landlord(s), and/or visitors. This allow us to have visitor access card.
-- Once we go full LDAP, this will go away.
create table if not exists person (id int not null auto_increment primary key, 
				    entrydate timestamp default current_timestamp, 
				    lang char(6),
				    firstname char(40) not null, 
				    name char(40) not null, 
				    nickname char(255) unique,
				    phonenumber char(20), 
				    emailaddress char(255) not null,
				    passwordhash char(127) not null, 
				    ldaphash char(127) not null, 
				    birthdate date,
				    openpgpkeyid char(40), 
--				    informations text not null,
				    sshpubkeys text,
				    machinestate char(40) not null,
				    machinestate_data text,
				    machinestate_expiration_date date -- Date when the state expires
				    );

-- Internal accounts - for memberships, drinks, hosting and other things you can imagine
create table if not exists internal_accounts (
				    structuredcomm char(21) unique not null primary key,
				    created_on timestamp default current_timestamp,
				    owner_id int, -- MySQL person owner ID: should go away
				    account_type char(20),
				    owner_dn char(255), -- LDAP person owner ID: should be primary
				    description text,
				    ref_dn char(255), -- Subject: membership or hosting
				    in_use TINYINT(1)
				    );

-- Alternate payment messages: for recent and not-so-recent fuckups
create table if not exists membership_fuckup_messages (member_id int not null,
				    fuckup_message char(60) unique not null);

-- Contractors and providers (electricity, water, gas, internet, insurance, bank,...)
-- Once we go full LDAP, this will go away
create table if not exists contractors (id int not null auto_increment primary key,
				    business_name char(30),
				    customer_id char(25), -- Usually our customer number
				    contract_id char(20),
				    website char(80),
				    username char(40), -- Credentials to log in to provider website
				    password char(40),
				    description text
				    );

-- Once we go full LDAP, this will go away
-- create table if not exists member_sponsors (id int not null auto_increment primary key,
--				    member_id int not null,
--				    sponsor_id int
--				    );

-- The history of the person state changes
create table if not exists person_history (id int not null auto_increment primary key,
				    member_id int not null,
				    member_dn char(255),
				    event_timestamp datetime,
				    machinestate char(40) not null,
				    machinestate_data text,
				    machinestate_expiration_date date,
				    freetext text
				    );

-- The new: hold every money movements
create table if not exists moneymovements (id int not null auto_increment primary key,
				    date_val date,
				    date_account date,
				    this_account char(40),
				    other_account char (40),
				    amount decimal (15,4) not null,
				    currency char (5) not null, -- should be enum
				    message char (255),
				    other_account_name char (50),
				    transaction_id char(255) unique not null,
				    fix_fuckup_msg char (60),
				    raw_csv_line text
				    );

create table if not exists expenses (id int not null auto_increment primary key,
				    submitter_id int not null,
				    description text not null,
				    dest_account char (40),
				    amount decimal (15,2) not null,
				    currency char (5) not null, -- should be enum
				    message char (60),
				    occurence int not null, -- should be enum
				    pay_method int not null, -- should be enum
				    deadline_date date,
				    submit_date date,
				    start_date date,
				    stop_date date,
				    flags int, -- should be a bitfield
				    category int not null, -- should be enum
				    in_year_seq_no int not null);
