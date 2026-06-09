ALTER TABLE `book_mark` ADD COLUMN `sort_alg` VARCHAR(50) DEFAULT 'RANDOM' AFTER `spell`;
ALTER TABLE `learning_dict` ADD COLUMN `sort_alg` VARCHAR(50) DEFAULT 'RANDOM' AFTER `fetch_mastered`;

