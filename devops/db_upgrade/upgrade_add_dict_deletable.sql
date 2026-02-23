ALTER TABLE dict ADD COLUMN deletable BOOLEAN NOT NULL DEFAULT TRUE;
UPDATE dict SET deletable = FALSE WHERE name = '生词本' OR name = '已掌握' OR owner_id = '15118';
