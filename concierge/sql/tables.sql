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
create table if not exists person (id int not null auto_increment primary key, 
				    entrydate date not null, 
				    structuredcomm char(21) unique not null, 
--				    altcomm char(21), -- This is supposed to disappear: migrate from old database
--				    altcomm2 char(21), -- This is supposed to disappear: migrate from old database
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
--                                    groupbits bigint not null default 0,
				    machinestate char(40) not null,
				    machinestate_data text,
				    machinestate_expiration_date date -- Date when the state expires
				    );

-- Alternate payment messages: from old application
create table if not exists old_comms (member_id int not null,
				    structuredcomm char(21) unique not null);

-- Alternate payment messages: for recent and not-so-recent fuckups
create table if not exists membership_fuckup_messages (member_id int not null,
				    fuckup_message char(60) unique not null);

-- List of available groups
create table if not exists hsb_groups (bit_id int not null auto_increment primary key,
				    shortdesc char(50) unique not null,
				    fulldesc text
				    );

-- Groups a person is member of
create table if not exists member_groups (id int not null auto_increment primary key,
				    member_id int not null,
				    group_id int not null
				    );

-- Contractors and providers (electricity, water, gas, internet, insurance, bank,...)
create table if not exists contractors (id int not null auto_increment primary key,
				    business_name char(30),
				    customer_id char(25), -- Usually our customer number
				    contract_id char(20),
				    website char(80),
				    username char(40), -- Credentials to log in to provider website
				    password char(40),
				    description text
				    );

create table if not exists member_sponsors (id int not null auto_increment primary key,
				    member_id int not null,
				    sponsor_id int
				    );

-- The history of the person state changes
create table if not exists person_history (id int not null auto_increment primary key,
				    member_id int not null,
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

create table if not exists user_tags (id int not null auto_increment primary key,
				    owner_id int,
				    tag_uid char(100),
				    validitystart timestamp default current_timestamp,
				    validityend timestamp,
				    tag_state int);

create table if not exists tag_states (id int not null auto_increment primary key,
				    shortdesc char(50) unique not null,
				    fulldesc text
				    );

-- Must go away: use an array instead
create table if not exists validiban (id int not null auto_increment primary key,
				    country char(2) unique not null,
				    validlength int not null);


-- Legacy: for JavaScript web interface
DROP TABLE IF EXISTS `logs_bell`;
CREATE TABLE `logs_bell` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

DROP TABLE IF EXISTS `logs_door`;
CREATE TABLE `logs_door` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `login` varchar(100) NOT NULL DEFAULT '',
  `date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

-- Old object: we assumed people in the database are effective members. This will disappear due to lack of flexibility.
create table if not exists hsbmembers (id int not null auto_increment primary key,
                                    entrydate date not null,
                                    structuredcomm char(21) unique not null,
                                    firstname char(30) not null,
                                    name char(30) not null,
                                    nickname char(30),
                                    phonenumber char(15),
                                    emailaddress char(60) not null,
                                    exitdate date,
                                    passwordhash char(60) not null default 'mouh',
                                    birthdate date,
                                    openpgpkeyid char(20),
                                    activateddate date,
                                    mail_flags bigint not null default 0,
                                    why_member text not null,
                                    json_data text,
                                    sshpubkeys text
                                    );

-- The old: this was designed to hold only the bank statements
create table if not exists bankstatements (id int not null auto_increment primary key,
				    date_val date,
				    date_account date,
				    this_account char(40),
				    other_account char (40),
				    amount decimal (15,4) not null,
				    currency char (5) not null, -- should be enum
				    message char (60),
				    other_account_name char (50),
				    transactionhash binary(20) unique not null,
				    fix_fuckup_msg char (60)
				    );

