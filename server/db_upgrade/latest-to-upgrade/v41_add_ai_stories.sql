-- Create ai_stories table for caching AI generated stories
CREATE TABLE `ai_stories` (
  `id` varchar(32) NOT NULL,
  `words_hash` varchar(64) NOT NULL COMMENT 'Sorted words hash for unique identification',
  `words_json` text NOT NULL COMMENT 'The list of words used',
  `story_content` mediumtext NOT NULL COMMENT 'The generated story content',
  `create_time` datetime DEFAULT NULL,
  `update_time` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_words_hash` (`words_hash`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
