ALTER TABLE dict ADD COLUMN base_dict_id VARCHAR(50) DEFAULT NULL;
COMMENT ON COLUMN dict.base_dict_id IS '对于衍生版词书（例如乱序版词书），指向其基础版词书的ID';

ALTER TABLE dict ADD COLUMN sort_alg VARCHAR(50) DEFAULT NULL;
COMMENT ON COLUMN dict.sort_alg IS '排序算法, 目前仅支持md5';
