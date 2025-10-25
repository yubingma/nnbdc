ALTER TABLE bdc.user CHANGE COLUMN invitedBy invitedById VARCHAR(32);
update bdc.user set level = '1' where level is null;
ALTER TABLE bdc.user CHANGE COLUMN level levelId VARCHAR(32) not null;