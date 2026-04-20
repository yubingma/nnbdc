-- Upgrade database from v37 to v38
-- Add description field to dict table

ALTER TABLE dict ADD COLUMN description VARCHAR(1000) DEFAULT NULL;

-- Update schema version (assuming there's a table for it, or just for reference)
-- UPDATE sys_config SET value = '38' WHERE key = 'schema_version';
