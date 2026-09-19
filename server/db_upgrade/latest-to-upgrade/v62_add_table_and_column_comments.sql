-- =============================================================================
-- 生产数据库表结构与字段注释补充脚本 (PostgreSQL 方言)
-- 
-- 说明: 基于现有生产库 (bdc) 实际表结构，对照 PO 实体类及业务领域模型，
-- 为所有表和字段补齐详尽、标准的中文注释，便于日常维护、排查与开发。
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 表: "ai_story" (AI单词情境故事表：DeepSeek生成的串记多词短文故事缓存)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "ai_story" IS 'AI单词情境故事表：DeepSeek生成的串记多词短文故事缓存';
COMMENT ON COLUMN "ai_story"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "ai_story"."words_hash" IS 'Sorted words hash for unique identification';
COMMENT ON COLUMN "ai_story"."words_json" IS 'The list of words used';
COMMENT ON COLUMN "ai_story"."story_content" IS 'The generated story content';
COMMENT ON COLUMN "ai_story"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "ai_story"."update_time" IS '最后更新时间';

-- -----------------------------------------------------------------------------
-- 表: "article" (精读短文与阅读素材表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "article" IS '精读短文与阅读素材表';
COMMENT ON COLUMN "article"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "article"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "article"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "article"."content" IS '内容详情';
COMMENT ON COLUMN "article"."description" IS '描述说明';
COMMENT ON COLUMN "article"."key_words" IS '文章关键词标签';
COMMENT ON COLUMN "article"."title" IS '标题';
COMMENT ON COLUMN "article"."viewed_count" IS '浏览次数/查看次数';
COMMENT ON COLUMN "article"."author" IS '作者/创建者';

-- -----------------------------------------------------------------------------
-- 表: "book_mark" (生词本/收藏夹分类标签表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "book_mark" IS '生词本/收藏夹分类标签表';
COMMENT ON COLUMN "book_mark"."book_mark_name" IS '生词本/书签分组名称';
COMMENT ON COLUMN "book_mark"."user_id" IS '关联的用户ID';
COMMENT ON COLUMN "book_mark"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "book_mark"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "book_mark"."position" IS '书签记录的单词在全词库中的绝对物理位次（从0开始，包含服务端全局词库）';
COMMENT ON COLUMN "book_mark"."spell" IS '书签记录的单词拼写';
COMMENT ON COLUMN "book_mark"."sort_alg" IS '书签内部单词的排序策略 (RANDOM/ALPHABETIC/FREQUENCY)';

-- -----------------------------------------------------------------------------
-- 表: "cigen" (英语词根词缀主表：存储词根词缀拼写、来源、核心含义)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "cigen" IS '英语词根词缀主表：存储词根词缀拼写、来源、核心含义';
COMMENT ON COLUMN "cigen"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "cigen"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "cigen"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "cigen"."description" IS '描述说明';
COMMENT ON COLUMN "cigen"."spell" IS '单词英文拼写';
COMMENT ON COLUMN "cigen"."category" IS '词根词缀分类 (前缀/词根/后缀)';
COMMENT ON COLUMN "cigen"."meaning_cn" IS '词根中文核心含义';
COMMENT ON COLUMN "cigen"."meaning_en" IS '词根英文核心含义';

-- -----------------------------------------------------------------------------
-- 表: "cigen_word_link" (单词与词根词缀关联表：记录单词与词根词缀的分解映射)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "cigen_word_link" IS '单词与词根词缀关联表：记录单词与词根词缀的分解映射';
COMMENT ON COLUMN "cigen_word_link"."cigen_id" IS '关联的词根ID';
COMMENT ON COLUMN "cigen_word_link"."word_id" IS '关联的单词ID';
COMMENT ON COLUMN "cigen_word_link"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "cigen_word_link"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "cigen_word_link"."the_explain" IS '该单词基于词根词缀的前缀/词根/后缀组合结构引申演化出当前词义的构词逻辑推导说明';

-- -----------------------------------------------------------------------------
-- 表: "daka" (用户打卡记录主表：记录用户每日完成学习计划的打卡流水)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "daka" IS '用户打卡记录主表：记录用户每日完成学习计划的打卡流水';
COMMENT ON COLUMN "daka"."for_learning_date" IS '【打卡履约业务日：0点对齐】本次打卡动作所履约核销的学习业务自然日（时分秒截断为 00:00:00）。核心业务规则：NBDC以当地凌晨 03:00 为分界线，00:00~02:59 熬夜打卡仍归属于前一天的业务日，此处记录的是目标业务日，与物理打卡时间 create_time/daka_time 严格区分';
COMMENT ON COLUMN "daka"."user_id" IS '关联的用户ID';
COMMENT ON COLUMN "daka"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "daka"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "daka"."text" IS '用户本次打卡填写的感言心得随笔文字';

-- -----------------------------------------------------------------------------
-- 表: "dict" (词书/词典基础信息表：存储各类官方词书、考试词书与自定义词库元信息)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "dict" IS '词书/词典基础信息表：存储各类官方词书、考试词书与自定义词库元信息';
COMMENT ON COLUMN "dict"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "dict"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "dict"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "dict"."is_ready" IS '【词书就绪铁律】词书是否准备就绪（true表示已冻结并发布供用户学习，此时严禁再修改词条；false表示草稿导入构建中）';
COMMENT ON COLUMN "dict"."is_shared" IS '【社区共享】对于用户自定义自建词书，指明该词书是否已公开发布共享给其他用户使用 (true/false)';
COMMENT ON COLUMN "dict"."name" IS '名称';
COMMENT ON COLUMN "dict"."word_count" IS '该单词书的单词数量';
COMMENT ON COLUMN "dict"."owner_id" IS '词书创建者用户ID（官方词书此字段为null）';
COMMENT ON COLUMN "dict"."visible" IS '词书是否在前端词库商场/列表中公开可见（部分历史老旧或测试词书设为false软下线隐藏）';
COMMENT ON COLUMN "dict"."popularity_limit" IS '【释义过滤阈值】当单词使用通用词典释义时，popularity 大于该设定的生僻释义项会被自动隐藏，避免释义过多干扰背诵；null表示不限制';
COMMENT ON COLUMN "dict"."deletable" IS '是否允许用户在客户端删除该词书本身（系统内置官方核心词书、生词本、已掌握词书固定为false不可删除）';
COMMENT ON COLUMN "dict"."editable" IS '是否允许用户对词书中的单词进行增删改编辑（用户自建词书、生词本为true，官方版权词书为false）';
COMMENT ON COLUMN "dict"."domain" IS '专业领域大类（如医学、计算机、商务英语、托福等，来源于导入时输入）';
COMMENT ON COLUMN "dict"."base_dict_id" IS '【衍生版词书追溯】指向其基础源词书的ID（例如乱序版词书基于顺序版派生，词条数据继承基础版，仅呈现顺序不同）';
COMMENT ON COLUMN "dict"."sort_alg" IS '词书默认选词排序算法：RANDOM(真乱序)/ALPHABETIC(A-Z字母序)/FREQUENCY(高频词优先)';
COMMENT ON COLUMN "dict"."description" IS '描述说明';

-- -----------------------------------------------------------------------------
-- 表: "dict_group" (词书分类组：如四六级、考研、托福雅思等分类大纲)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "dict_group" IS '词书分类组：如四六级、考研、托福雅思等分类大纲';
COMMENT ON COLUMN "dict_group"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "dict_group"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "dict_group"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "dict_group"."display_index" IS '词书分类展示排序索引';
COMMENT ON COLUMN "dict_group"."name" IS '名称';
COMMENT ON COLUMN "dict_group"."parent_id" IS '父级分类组ID（顶级分类为空）';

-- -----------------------------------------------------------------------------
-- 表: "dict_word" (词书与单词关联表：记录某本词书包含哪些单词及词序/单元分组)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "dict_word" IS '词书与单词关联表：记录某本词书包含哪些单词及词序/单元分组';
COMMENT ON COLUMN "dict_word"."dict_id" IS '关联的词书ID';
COMMENT ON COLUMN "dict_word"."word_id" IS '关联的单词ID';
COMMENT ON COLUMN "dict_word"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "dict_word"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "dict_word"."seq" IS '【绝对位次】单词在该词书中的物理排位顺序号（从1开始递增，决定正序模式下的背诵顺序）';
COMMENT ON COLUMN "dict_word"."unit" IS '【单元章节划分】所属单元章节名称（如: Unit 1, List 3，支持用户按单元分段背诵）';

-- -----------------------------------------------------------------------------
-- 表: "email_verification_code" (邮箱验证码发送与核验记录表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "email_verification_code" IS '邮箱验证码发送与核验记录表';
COMMENT ON COLUMN "email_verification_code"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "email_verification_code"."email" IS '接收验证码的电子邮箱';
COMMENT ON COLUMN "email_verification_code"."code" IS '6位数字邮箱验证码';
COMMENT ON COLUMN "email_verification_code"."type" IS '类型';
COMMENT ON COLUMN "email_verification_code"."expire_time" IS 'expire时间戳';
COMMENT ON COLUMN "email_verification_code"."used" IS '验证码是否已被核销使用 (true/false)';
COMMENT ON COLUMN "email_verification_code"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "email_verification_code"."update_time" IS '最后更新时间';

-- -----------------------------------------------------------------------------
-- 表: "error_report" (客户端异常错误日志上报收集表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "error_report" IS '客户端异常错误日志上报收集表';
COMMENT ON COLUMN "error_report"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "error_report"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "error_report"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "error_report"."content" IS '内容详情';
COMMENT ON COLUMN "error_report"."fixed" IS '报错问题是否已被管理员修复处理 (true/false)';
COMMENT ON COLUMN "error_report"."word" IS '单词拼写';
COMMENT ON COLUMN "error_report"."user_id" IS '关联的用户ID';
COMMENT ON COLUMN "error_report"."image_files" IS '报错附带的截图文件路径或OSS标识';

-- -----------------------------------------------------------------------------
-- 表: "event" (埋点与业务事件记录表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "event" IS '埋点与业务事件记录表';
COMMENT ON COLUMN "event"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "event"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "event"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "event"."event_type" IS '业务埋点事件类型';
COMMENT ON COLUMN "event"."user_id" IS '关联的用户ID';
COMMENT ON COLUMN "event"."word_image_id" IS '关联的单词插图ID';
COMMENT ON COLUMN "event"."word_short_desc_chinese_id" IS '关联的单词中文简释ID';
COMMENT ON COLUMN "event"."sentence_id" IS '关联的例句ID';
COMMENT ON COLUMN "event"."sentence_chinese_id" IS '关联的例句翻译ID';

-- -----------------------------------------------------------------------------
-- 表: "feature_request" (用户需求与功能建议表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "feature_request" IS '用户需求与功能建议表';
COMMENT ON COLUMN "feature_request"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "feature_request"."creator_id" IS '需求建议提出人用户ID';
COMMENT ON COLUMN "feature_request"."title" IS '标题';
COMMENT ON COLUMN "feature_request"."content" IS '内容详情';
COMMENT ON COLUMN "feature_request"."status" IS '状态标识';
COMMENT ON COLUMN "feature_request"."vote_count" IS 'vote统计计数值';
COMMENT ON COLUMN "feature_request"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "feature_request"."update_time" IS '最后更新时间';

-- -----------------------------------------------------------------------------
-- 表: "feature_request_report" (需求建议举报记录表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "feature_request_report" IS '需求建议举报记录表';
COMMENT ON COLUMN "feature_request_report"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "feature_request_report"."reporter_id" IS '举报人用户ID';
COMMENT ON COLUMN "feature_request_report"."feature_request_id" IS '被举报的需求建议ID';
COMMENT ON COLUMN "feature_request_report"."content" IS '内容详情';
COMMENT ON COLUMN "feature_request_report"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "feature_request_report"."update_time" IS '最后更新时间';

-- -----------------------------------------------------------------------------
-- 表: "feature_request_vote" (需求建议点赞投票表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "feature_request_vote" IS '需求建议点赞投票表';
COMMENT ON COLUMN "feature_request_vote"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "feature_request_vote"."request_id" IS '被投票支持的需求建议ID';
COMMENT ON COLUMN "feature_request_vote"."user_id" IS '关联的用户ID';
COMMENT ON COLUMN "feature_request_vote"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "feature_request_vote"."update_time" IS '最后更新时间';

-- -----------------------------------------------------------------------------
-- 表: "forum" (社区交流板块表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "forum" IS '社区交流板块表';
COMMENT ON COLUMN "forum"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "forum"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "forum"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "forum"."name" IS '名称';

-- -----------------------------------------------------------------------------
-- 表: "forum_and_manager_link" (社区版块与版主管理员关联表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "forum_and_manager_link" IS '社区版块与版主管理员关联表';
COMMENT ON COLUMN "forum_and_manager_link"."forum_id" IS '所属论坛版块ID';
COMMENT ON COLUMN "forum_and_manager_link"."user_id" IS '关联的用户ID';
COMMENT ON COLUMN "forum_and_manager_link"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "forum_and_manager_link"."update_time" IS '最后更新时间';

-- -----------------------------------------------------------------------------
-- 表: "forum_post" (社区帖子主表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "forum_post" IS '社区帖子主表';
COMMENT ON COLUMN "forum_post"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "forum_post"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "forum_post"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "forum_post"."browse_count" IS 'browse统计计数值';
COMMENT ON COLUMN "forum_post"."last_reply_time" IS 'last_reply时间戳';
COMMENT ON COLUMN "forum_post"."post_content" IS '社区帖子正文内容';
COMMENT ON COLUMN "forum_post"."post_title" IS '社区帖子标题';
COMMENT ON COLUMN "forum_post"."reply_count" IS 'reply统计计数值';
COMMENT ON COLUMN "forum_post"."forum_id" IS '所属社区版块ID';
COMMENT ON COLUMN "forum_post"."post_creator_id" IS '发帖人用户ID';

-- -----------------------------------------------------------------------------
-- 表: "forum_post_reply" (社区帖子回复明细表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "forum_post_reply" IS '社区帖子回复明细表';
COMMENT ON COLUMN "forum_post_reply"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "forum_post_reply"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "forum_post_reply"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "forum_post_reply"."content" IS '内容详情';
COMMENT ON COLUMN "forum_post_reply"."post_id" IS '所属主帖ID';
COMMENT ON COLUMN "forum_post_reply"."post_replyer_id" IS '回帖人用户ID';

-- -----------------------------------------------------------------------------
-- 表: "game_hall" (背单词小游戏大厅/房间配置表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "game_hall" IS '背单词小游戏大厅/房间配置表';
COMMENT ON COLUMN "game_hall"."game_type" IS '小游戏类型标识';
COMMENT ON COLUMN "game_hall"."hall_name" IS '游戏大厅/房间显示名称';
COMMENT ON COLUMN "game_hall"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "game_hall"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "game_hall"."base_point" IS '游戏底分底注';
COMMENT ON COLUMN "game_hall"."display_order" IS '大厅展示排序序号';
COMMENT ON COLUMN "game_hall"."dict_group_id" IS '对应学习词书分类ID';
COMMENT ON COLUMN "game_hall"."hall_group_id" IS '对应大厅分组ID';
COMMENT ON COLUMN "game_hall"."id" IS '主键ID (32位UUID)';

-- -----------------------------------------------------------------------------
-- 表: "get_pwd_log" (密码找回安全审计日志表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "get_pwd_log" IS '密码找回安全审计日志表';
COMMENT ON COLUMN "get_pwd_log"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "get_pwd_log"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "get_pwd_log"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "get_pwd_log"."content" IS '内容详情';
COMMENT ON COLUMN "get_pwd_log"."result" IS '找回密码邮件发送结果说明';
COMMENT ON COLUMN "get_pwd_log"."send_time" IS 'send时间戳';
COMMENT ON COLUMN "get_pwd_log"."to_email" IS '接收重置密码邮件的目标邮箱';

-- -----------------------------------------------------------------------------
-- 表: "group_and_dict_link" (词书分类组与具体词书多对多关联表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "group_and_dict_link" IS '词书分类组与具体词书多对多关联表';
COMMENT ON COLUMN "group_and_dict_link"."group_id" IS '关联的词书大纲分类组ID';
COMMENT ON COLUMN "group_and_dict_link"."dict_id" IS '关联的词书ID';
COMMENT ON COLUMN "group_and_dict_link"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "group_and_dict_link"."update_time" IS '最后更新时间';

-- -----------------------------------------------------------------------------
-- 表: "hall_group" (游戏大厅分组)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "hall_group" IS '游戏大厅分组';
COMMENT ON COLUMN "hall_group"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "hall_group"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "hall_group"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "hall_group"."display_order" IS '游戏大厅分组展示排序';
COMMENT ON COLUMN "hall_group"."game_type" IS '所属游戏类型';
COMMENT ON COLUMN "hall_group"."group_name" IS '游戏大厅分组名称';

-- -----------------------------------------------------------------------------
-- 表: "id_gen" (分布式/全局序列表主键生成辅助表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "id_gen" IS '分布式/全局序列表主键生成辅助表';
COMMENT ON COLUMN "id_gen"."sequence_name" IS '分布式全局序列名称';
COMMENT ON COLUMN "id_gen"."next_val" IS '下一个自增序号值';
COMMENT ON COLUMN "id_gen"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "id_gen"."update_time" IS '最后更新时间';

-- -----------------------------------------------------------------------------
-- 表: "import_task" (单词导入任务表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "import_task" IS '单词导入任务表';
COMMENT ON COLUMN "import_task"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "import_task"."status" IS '状态标识';
COMMENT ON COLUMN "import_task"."total_words" IS '任务待导入词汇总数';
COMMENT ON COLUMN "import_task"."processed_words" IS '任务已处理完成词汇数';
COMMENT ON COLUMN "import_task"."log" IS '导入执行详细日志';
COMMENT ON COLUMN "import_task"."config" IS '导入任务配置JSON';
COMMENT ON COLUMN "import_task"."file_name" IS '导入原始文件名';
COMMENT ON COLUMN "import_task"."owner_id" IS '发起导入任务的用户ID';
COMMENT ON COLUMN "import_task"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "import_task"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "import_task"."results" IS '导入最终结果统计摘要';

-- -----------------------------------------------------------------------------
-- 表: "info_vote_log" (单词补充信息有用/无用点赞投票日志表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "info_vote_log" IS '单词补充信息有用/无用点赞投票日志表';
COMMENT ON COLUMN "info_vote_log"."info_id" IS '被投票的补充信息/简释ID';
COMMENT ON COLUMN "info_vote_log"."user_id" IS '关联的用户ID';
COMMENT ON COLUMN "info_vote_log"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "info_vote_log"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "info_vote_log"."vote_time" IS 'vote时间戳';
COMMENT ON COLUMN "info_vote_log"."vote_type" IS '投票评价类型 (UP赞 / DOWN踩)';

-- -----------------------------------------------------------------------------
-- 表: "learning_dict" (用户学习词书配置：记录用户当前正在学习的词书及顺序模式)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "learning_dict" IS '用户学习词书配置：记录用户当前正在学习的词书及顺序模式';
COMMENT ON COLUMN "learning_dict"."dict_id" IS '关联的词书ID';
COMMENT ON COLUMN "learning_dict"."user_id" IS '关联的用户ID';
COMMENT ON COLUMN "learning_dict"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "learning_dict"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "learning_dict"."is_privileged" IS '是否privileged标识 (true/false)';
COMMENT ON COLUMN "learning_dict"."fetch_mastered" IS '如果某单词已经掌握，是否还是要从词书取出该单词进行学习?';
COMMENT ON COLUMN "learning_dict"."sort_alg" IS '词书选词排序算法 (RANDOM/ALPHABETIC/FREQUENCY)';

-- -----------------------------------------------------------------------------
-- 表: "learning_log" (单词学习历史记录表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "learning_log" IS '单词学习历史记录表';
COMMENT ON COLUMN "learning_log"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "learning_log"."user_id" IS '关联的用户ID';
COMMENT ON COLUMN "learning_log"."word_id" IS '关联的单词ID';
COMMENT ON COLUMN "learning_log"."rating" IS '评分 (1: Again, 2: Hard, 3: Good, 4: Easy)';
COMMENT ON COLUMN "learning_log"."stability" IS 'FSRS算法记忆稳定性指标 (Stability)';
COMMENT ON COLUMN "learning_log"."difficulty" IS 'FSRS算法词汇记忆难度指标 (Difficulty)';
COMMENT ON COLUMN "learning_log"."elapsed_days" IS '距上次复习流逝的天数';
COMMENT ON COLUMN "learning_log"."scheduled_days" IS '算法推荐调度的复习间隔天数';
COMMENT ON COLUMN "learning_log"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "learning_log"."update_time" IS '最后更新时间';

-- -----------------------------------------------------------------------------
-- 表: "learning_word" (用户单词学习进度表：记录用户对各单词的掌握程度、掌握时间及复习加餐状态)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "learning_word" IS '用户单词学习进度表：记录用户对各单词的掌握程度、掌握时间及复习加餐状态';
COMMENT ON COLUMN "learning_word"."user_id" IS '关联的用户ID';
COMMENT ON COLUMN "learning_word"."word_id" IS '关联的单词ID';
COMMENT ON COLUMN "learning_word"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "learning_word"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "learning_word"."add_day" IS '【用户背词日序数：注意是整数序号而非日期】用户从首次使用背单词以来的第几个学习业务日序号（相对自然天数序号，从1开始递增，如第1天抓新词为1，跨业务日再次抓词为2，以此类推。特别注意：本字段为 INTEGER，非日历日期，亦非时间戳！）';
COMMENT ON COLUMN "learning_word"."add_time" IS '【入库物理时刻】该单词首次被系统加入用户个人学习词库的精确物理时间戳';
COMMENT ON COLUMN "learning_word"."last_learning_date" IS '【最近学词时刻：精确时间戳】该单词最近一次被用户学习、复习答题或测验通过的具体时间戳（虽列名为date，但实际存储完整TIMESTAMP，精确到毫秒）';
COMMENT ON COLUMN "learning_word"."learning_order" IS '当日学习任务中该单词出词的流水序号';
COMMENT ON COLUMN "learning_word"."is_today_new_word" IS '是否是新词。本属性仅对今日学习中的单词有意义。 为本属性赋值的逻辑是： 当从学习中单词列表选择今日单词时，判断所选单词的已学习次数，如果已学习次数为0，则本属性赋值为true';
COMMENT ON COLUMN "learning_word"."learned_times" IS '已学习次数，一个单词完成一天的学习，这个值增加的值一般大于1（因为用户一般会选择多个学习步骤）';
COMMENT ON COLUMN "learning_word"."batch_id" IS '【今日任务调度批次】>0表示该词已被调度进入今日的学习或复习队列中；=0表示未激活沉睡在待学词库中';
COMMENT ON COLUMN "learning_word"."today_learned_times" IS '今日已学习次数';
COMMENT ON COLUMN "learning_word"."stability" IS '【FSRS现代记忆算法】记忆留存稳定性指标值（数值大小等于该记忆能以90%概率保留的天数，越大记忆越牢固）';
COMMENT ON COLUMN "learning_word"."difficulty" IS '【FSRS现代记忆算法】单词固有认知难度评分（1-10，数值越高表示对该用户而言越难记）';
COMMENT ON COLUMN "learning_word"."elapsed_days" IS '【距上次复习流逝天数】FSRS记忆算法核心输入参数，表示距离上一次复习该词已实际流逝的自然天数（整数）';
COMMENT ON COLUMN "learning_word"."scheduled_days" IS '【算法推荐复习间隔】FSRS记忆算法为该词计算推荐的最佳下次复习理论间隔天数（整数）';
COMMENT ON COLUMN "learning_word"."reps" IS '在所有复习中成功回忆并答对该词的累计连续次数';
COMMENT ON COLUMN "learning_word"."lapses" IS '遗忘失误次数（在复习中点击「不认识」或选择题选错的累计总次数）';
COMMENT ON COLUMN "learning_word"."state" IS 'FSRS 状态: 0: New (新词), 1: Learning (学习中), 2: Review (复习), 3: Relearning (重学)';
COMMENT ON COLUMN "learning_word"."is_extra" IS '【关键业务标记：加餐词】用户当日打卡完成后追加背诵的加餐词为TRUE。加餐词复用本表与流程，但严禁计入今日打卡进度环与额度分母；跨天重置或削减时客户端必须将其置回FALSE';

-- -----------------------------------------------------------------------------
-- 表: "level" (用户学习等级阶梯规则表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "level" IS '用户学习等级阶梯规则表';
COMMENT ON COLUMN "level"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "level"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "level"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "level"."figure" IS '等级段位称号形象标识';
COMMENT ON COLUMN "level"."level" IS '用户等级数字 (1, 2, ...)';
COMMENT ON COLUMN "level"."max_score" IS '该等级所需最高积分';
COMMENT ON COLUMN "level"."min_score" IS '该等级起步最低积分';
COMMENT ON COLUMN "level"."name" IS '名称';
COMMENT ON COLUMN "level"."style" IS '等级称号展示UI样式';

-- -----------------------------------------------------------------------------
-- 表: "login_log" (用户登录历史与IP审计日志表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "login_log" IS '用户登录历史与IP审计日志表';
COMMENT ON COLUMN "login_log"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "login_log"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "login_log"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "login_log"."login_time" IS 'login时间戳';
COMMENT ON COLUMN "login_log"."user_id" IS '关联的用户ID';

-- -----------------------------------------------------------------------------
-- 表: "meaning_item" (单词释义表：存储单词各词性的具体中文释义及释义热度)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "meaning_item" IS '单词释义表：存储单词各词性的具体中文释义及释义热度';
COMMENT ON COLUMN "meaning_item"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "meaning_item"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "meaning_item"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "meaning_item"."ci_xing" IS '词性标准英文缩写（如 n.名词, v.动词, vt.及物动词, vi.不及物动词, adj.形容词, adv.副词, prep.介词 等）';
COMMENT ON COLUMN "meaning_item"."meaning" IS '该词性下的具体中文核心释义文本';
COMMENT ON COLUMN "meaning_item"."word_id" IS '释义所属单词';
COMMENT ON COLUMN "meaning_item"."dict_id" IS '关联的词书ID';
COMMENT ON COLUMN "meaning_item"."is_updating" IS '是否正在更新中（例如由 AI 异步补全中）';
COMMENT ON COLUMN "meaning_item"."updating_start_at" IS '开始更新的时间';
COMMENT ON COLUMN "meaning_item"."popularity" IS '释义项语料库使用频率排序值（越小越核心常见）';
COMMENT ON COLUMN "meaning_item"."owner_id" IS '释义的所有者（用户）。 1. 性能优化：在拉取单词释义时，可直接通过 owner_id 过滤（公共资源 + 我的私有资源），避免通过词书表进行复杂的跨表 JOIN。 2. UGC 隔离：支持用户在公共词书下记录仅自己可见的私有解释或笔记。 归属规则： - 系统/共享资源：归属于系统管理员 (Constants.SYS_USER_SYS_ID，即 "15118")。 - 用户私有资源：归属于该特定的学习用户。';
COMMENT ON COLUMN "meaning_item"."popularity_percent" IS '该释义项在全英语料库日常使用中的统计出现占比百分比（0-100）';

-- -----------------------------------------------------------------------------
-- 表: "msg" (站内信与系统消息通知表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "msg" IS '站内信与系统消息通知表';
COMMENT ON COLUMN "msg"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "msg"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "msg"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "msg"."content" IS '内容详情';
COMMENT ON COLUMN "msg"."msg_type" IS '站内信类型 (系统通知/同桌消息/活动提醒)';
COMMENT ON COLUMN "msg"."from_user_id" IS '消息发送方用户ID（系统为 sys）';
COMMENT ON COLUMN "msg"."to_user_id" IS '消息接收方用户ID';
COMMENT ON COLUMN "msg"."viewed" IS '消息是否已被接收方阅读 (true/false)';
COMMENT ON COLUMN "msg"."client_type" IS '目标客户端类型 (ios/android/web)';

-- -----------------------------------------------------------------------------
-- 表: "pay_order" (支付订单表：微信/支付宝/苹果IAP支付流水记录)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "pay_order" IS '支付订单表：微信/支付宝/苹果IAP支付流水记录';
COMMENT ON COLUMN "pay_order"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "pay_order"."user_id" IS '关联的用户ID';
COMMENT ON COLUMN "pay_order"."product_id" IS '关联的product标识ID';
COMMENT ON COLUMN "pay_order"."amount" IS '订单实际支付交易金额（单位：元）';
COMMENT ON COLUMN "pay_order"."channel" IS '第三方支付渠道标识：WECHAT_PAY(微信支付)/ALIPAY(支付宝)/APPLE_IAP(苹果内购)/HUAWEI_IAP(华为内购)';
COMMENT ON COLUMN "pay_order"."status" IS '状态标识';
COMMENT ON COLUMN "pay_order"."outer_trade_no" IS '第三方渠道侧外部交易单号';
COMMENT ON COLUMN "pay_order"."pay_time" IS 'pay时间戳';
COMMENT ON COLUMN "pay_order"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "pay_order"."update_time" IS '最后更新时间';

-- -----------------------------------------------------------------------------
-- 表: "pca_projection_config" (词向量降维投影配置表（用于词汇星系3D可视化）)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "pca_projection_config" IS '词向量降维投影配置表（用于词汇星系3D可视化）';
COMMENT ON COLUMN "pca_projection_config"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "pca_projection_config"."config_json" IS '词向量降维投影矩阵参数JSON（用于3D词汇星系）';
COMMENT ON COLUMN "pca_projection_config"."update_time" IS '最后更新时间';

-- -----------------------------------------------------------------------------
-- 表: "promo_activity" (营销推广活动与优惠券发放规则表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "promo_activity" IS '营销推广活动与优惠券发放规则表';
COMMENT ON COLUMN "promo_activity"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "promo_activity"."activity_code" IS '推广活动唯一代号';
COMMENT ON COLUMN "promo_activity"."name" IS '名称';
COMMENT ON COLUMN "promo_activity"."duration" IS '兑换赠送的会员时长数值';
COMMENT ON COLUMN "promo_activity"."start_time" IS 'start时间戳';
COMMENT ON COLUMN "promo_activity"."end_time" IS 'end时间戳';
COMMENT ON COLUMN "promo_activity"."max_redemptions" IS '活动最大允许总兑换次数限制';
COMMENT ON COLUMN "promo_activity"."redemption_count" IS 'redemption统计计数值';
COMMENT ON COLUMN "promo_activity"."is_active" IS '活动当前是否处于开启激活状态 (true:可兑换 / false:已停用下线)';
COMMENT ON COLUMN "promo_activity"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "promo_activity"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "promo_activity"."show_code_to_user" IS '是否在界面向用户直接展示兑换码 (true/false)';
COMMENT ON COLUMN "promo_activity"."show_redeem_ui" IS '是否在客户端个人中心展示优惠兑换入口UI (true/false)';
COMMENT ON COLUMN "promo_activity"."reply_message" IS '兑换成功时自动回复提示语';

-- -----------------------------------------------------------------------------
-- 表: "promo_redemption" (营销兑换码核销使用记录表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "promo_redemption" IS '营销兑换码核销使用记录表';
COMMENT ON COLUMN "promo_redemption"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "promo_redemption"."user_id" IS '关联的用户ID';
COMMENT ON COLUMN "promo_redemption"."activity_id" IS '关联的activity标识ID';
COMMENT ON COLUMN "promo_redemption"."redeem_time" IS 'redeem时间戳';
COMMENT ON COLUMN "promo_redemption"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "promo_redemption"."update_time" IS '最后更新时间';

-- -----------------------------------------------------------------------------
-- 表: "sentence" (原声例句主表：存储英文例句原句、音频文件路径及引用信息)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "sentence" IS '原声例句主表：存储英文例句原句、音频文件路径及引用信息';
COMMENT ON COLUMN "sentence"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "sentence"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "sentence"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "sentence"."english" IS '英文原版原声例句文本';
COMMENT ON COLUMN "sentence"."chinese" IS '官方/首选权威中文翻译';
COMMENT ON COLUMN "sentence"."english_digest" IS '【例句去重哈希】英文原句小写去除标点后的MD5哈希摘要（用于全局例句极速查重，杜绝重复收录）';
COMMENT ON COLUMN "sentence"."last_diy_update_time" IS 'last_diy_update时间戳';
COMMENT ON COLUMN "sentence"."the_type" IS '例句类型（原声/双语/影视等）';
COMMENT ON COLUMN "sentence"."producer" IS '例句音源制作方/版权方';
COMMENT ON COLUMN "sentence"."need_tts" IS '【原声缺失标记】该例句是否缺失原声发音、需要后台调用大模型TTS语音合成补齐 (true/false)';
COMMENT ON COLUMN "sentence"."foot_count" IS 'foot统计计数值';
COMMENT ON COLUMN "sentence"."hand_count" IS 'hand统计计数值';
COMMENT ON COLUMN "sentence"."author_id" IS '例句录入者用户ID';
COMMENT ON COLUMN "sentence"."meaning_item_id" IS '关联的释义项ID';
COMMENT ON COLUMN "sentence"."word_meaning" IS '该例句中目标单词所对应的具体释义';
COMMENT ON COLUMN "sentence"."temp_sound_url" IS '待转存处理的临时音频下载URL';
COMMENT ON COLUMN "sentence"."is_updating" IS '是否updating标识 (true/false)';
COMMENT ON COLUMN "sentence"."updating_start_at" IS '音频异步抓取更新开始时间';
COMMENT ON COLUMN "sentence"."popularity" IS '例句热度推荐权重值';
COMMENT ON COLUMN "sentence"."part_of_speech" IS '该例句中匹配词的词性缩写';
COMMENT ON COLUMN "sentence"."tts_voice" IS 'TTS语音合成发音人音色（如火山引擎豆包语音发音人代号）';
COMMENT ON COLUMN "sentence"."tts_engine" IS 'TTS语音合成引擎（如 VOLCANO_TTS）';
COMMENT ON COLUMN "sentence"."tts_instruction" IS 'TTS语音合成情感/语速指令';
COMMENT ON COLUMN "sentence"."owner_id" IS '例句归属人ID';

-- -----------------------------------------------------------------------------
-- 表: "sentence_chinese" (例句中文翻译表：存储英文例句对应的一对多中文翻译)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "sentence_chinese" IS '例句中文翻译表：存储英文例句对应的一对多中文翻译';
COMMENT ON COLUMN "sentence_chinese"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "sentence_chinese"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "sentence_chinese"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "sentence_chinese"."content" IS '内容详情';
COMMENT ON COLUMN "sentence_chinese"."foot_count" IS 'foot统计计数值';
COMMENT ON COLUMN "sentence_chinese"."hand_count" IS 'hand统计计数值';
COMMENT ON COLUMN "sentence_chinese"."item_type" IS '中文翻译类型 (官方/用户贡献)';
COMMENT ON COLUMN "sentence_chinese"."author" IS '作者/创建者';
COMMENT ON COLUMN "sentence_chinese"."sentence_id" IS '关联的例句ID';

-- -----------------------------------------------------------------------------
-- 表: "sentence_chinese_remark" (例句中文翻译点评与纠错说明)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "sentence_chinese_remark" IS '例句中文翻译点评与纠错说明';
COMMENT ON COLUMN "sentence_chinese_remark"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "sentence_chinese_remark"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "sentence_chinese_remark"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "sentence_chinese_remark"."content" IS '内容详情';
COMMENT ON COLUMN "sentence_chinese_remark"."chinese_id" IS '关联的例句中文翻译ID';
COMMENT ON COLUMN "sentence_chinese_remark"."author" IS '作者/创建者';

-- -----------------------------------------------------------------------------
-- 表: "sentence_update_notify" (例句更新通知与变更事件)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "sentence_update_notify" IS '例句更新通知与变更事件';
COMMENT ON COLUMN "sentence_update_notify"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "sentence_update_notify"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "sentence_update_notify"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "sentence_update_notify"."sentence_id" IS '关联的例句ID';

-- -----------------------------------------------------------------------------
-- 表: "similar_word" (形近词关联表：记录拼写容易混淆的形似单词映射)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "similar_word" IS '形近词关联表：记录拼写容易混淆的形似单词映射';
COMMENT ON COLUMN "similar_word"."word_id" IS '关联的单词ID';
COMMENT ON COLUMN "similar_word"."similar_word_id" IS '关联的形似混淆单词ID';
COMMENT ON COLUMN "similar_word"."distance" IS '编辑距离/拼写形似度度量值';
COMMENT ON COLUMN "similar_word"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "similar_word"."update_time" IS '最后更新时间';

-- -----------------------------------------------------------------------------
-- 表: "study_group" (同桌/学习小组主表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "study_group" IS '同桌/学习小组主表';
COMMENT ON COLUMN "study_group"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "study_group"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "study_group"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "study_group"."cow_dung" IS '学习小组公用牛粪积分池';
COMMENT ON COLUMN "study_group"."group_name" IS '学习小组名称';
COMMENT ON COLUMN "study_group"."group_remark" IS '学习小组简介/组规公告';
COMMENT ON COLUMN "study_group"."group_title" IS '学习小组头衔称号';
COMMENT ON COLUMN "study_group"."creator_id" IS '小组创建者/组长用户ID';
COMMENT ON COLUMN "study_group"."grade_id" IS '关联的小组等级评定ID';

-- -----------------------------------------------------------------------------
-- 表: "study_group_and_manager_link" (学习小组组长与管理员关联表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "study_group_and_manager_link" IS '学习小组组长与管理员关联表';
COMMENT ON COLUMN "study_group_and_manager_link"."group_id" IS '关联的学习小组ID';
COMMENT ON COLUMN "study_group_and_manager_link"."user_id" IS '关联的用户ID';
COMMENT ON COLUMN "study_group_and_manager_link"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "study_group_and_manager_link"."update_time" IS '最后更新时间';

-- -----------------------------------------------------------------------------
-- 表: "study_group_and_user_link" (学习小组与成员加入关系表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "study_group_and_user_link" IS '学习小组与成员加入关系表';
COMMENT ON COLUMN "study_group_and_user_link"."group_id" IS '关联的学习小组ID';
COMMENT ON COLUMN "study_group_and_user_link"."user_id" IS '组员用户ID';
COMMENT ON COLUMN "study_group_and_user_link"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "study_group_and_user_link"."update_time" IS '最后更新时间';

-- -----------------------------------------------------------------------------
-- 表: "study_group_grade" (学习小组等级规则表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "study_group_grade" IS '学习小组等级规则表';
COMMENT ON COLUMN "study_group_grade"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "study_group_grade"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "study_group_grade"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "study_group_grade"."max_user_count" IS 'max_user统计计数值';
COMMENT ON COLUMN "study_group_grade"."name" IS '名称';

-- -----------------------------------------------------------------------------
-- 表: "study_group_post" (学习小组成员动态/发言表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "study_group_post" IS '学习小组成员动态/发言表';
COMMENT ON COLUMN "study_group_post"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "study_group_post"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "study_group_post"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "study_group_post"."browse_count" IS 'browse统计计数值';
COMMENT ON COLUMN "study_group_post"."last_reply_time" IS 'last_reply时间戳';
COMMENT ON COLUMN "study_group_post"."post_content" IS '学习小组动态正文内容';
COMMENT ON COLUMN "study_group_post"."post_title" IS '学习小组动态标题';
COMMENT ON COLUMN "study_group_post"."reply_count" IS 'reply统计计数值';
COMMENT ON COLUMN "study_group_post"."group_id" IS '所属学习小组ID';
COMMENT ON COLUMN "study_group_post"."post_creator_id" IS '发帖组员用户ID';

-- -----------------------------------------------------------------------------
-- 表: "study_group_post_reply" (学习小组动态回复表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "study_group_post_reply" IS '学习小组动态回复表';
COMMENT ON COLUMN "study_group_post_reply"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "study_group_post_reply"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "study_group_post_reply"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "study_group_post_reply"."content" IS '内容详情';
COMMENT ON COLUMN "study_group_post_reply"."post_id" IS '所属小组动态主帖ID';
COMMENT ON COLUMN "study_group_post_reply"."post_replyer_id" IS '回复组员用户ID';

-- -----------------------------------------------------------------------------
-- 表: "study_group_snapshot_daily" (学习小组每日综合得分与排名快照表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "study_group_snapshot_daily" IS '学习小组每日综合得分与排名快照表';
COMMENT ON COLUMN "study_group_snapshot_daily"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "study_group_snapshot_daily"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "study_group_snapshot_daily"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "study_group_snapshot_daily"."cow_dung" IS '当日小组牛粪总数快照';
COMMENT ON COLUMN "study_group_snapshot_daily"."daka_ratio" IS '当日小组打卡率快照';
COMMENT ON COLUMN "study_group_snapshot_daily"."daka_score" IS '当日小组打卡总积分快照';
COMMENT ON COLUMN "study_group_snapshot_daily"."game_score" IS '当日小组游戏总积分快照';
COMMENT ON COLUMN "study_group_snapshot_daily"."member_count" IS 'member统计计数值';
COMMENT ON COLUMN "study_group_snapshot_daily"."order_no" IS '排序号/序号';
COMMENT ON COLUMN "study_group_snapshot_daily"."the_date" IS '【小组每日快照归属日】学习小组每日积分、打卡率及排名榜单备份快照归属的业务自然日（时分秒对齐为 00:00:00）';
COMMENT ON COLUMN "study_group_snapshot_daily"."group_id" IS '关联的学习小组ID';

-- -----------------------------------------------------------------------------
-- 表: "synonym" (同义词关联表：记录单词之间的同义/近义映射关系)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "synonym" IS '同义词关联表：记录单词之间的同义/近义映射关系';
COMMENT ON COLUMN "synonym"."meaning_item_id" IS '关联的释义项ID';
COMMENT ON COLUMN "synonym"."word_id" IS '关联的单词ID';
COMMENT ON COLUMN "synonym"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "synonym"."update_time" IS '最后更新时间';

-- -----------------------------------------------------------------------------
-- 表: "sys_db_log" (系统基础数据（词库/例句等）增量变更同步日志表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "sys_db_log" IS '系统基础数据（词库/例句等）增量变更同步日志表';
COMMENT ON COLUMN "sys_db_log"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "sys_db_log"."version" IS '版本号';
COMMENT ON COLUMN "sys_db_log"."operate" IS '变更操作动作：INSERT/UPDATE/DELETE';
COMMENT ON COLUMN "sys_db_log"."tbl_name" IS '系统基础数据变更的目标表名（必须严格使用单数下划线命名）';
COMMENT ON COLUMN "sys_db_log"."record_id" IS '被变更的系统基础数据记录主键ID';
COMMENT ON COLUMN "sys_db_log"."record" IS '系统基础数据变更行全量JSON字符串';
COMMENT ON COLUMN "sys_db_log"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "sys_db_log"."update_time" IS '最后更新时间';

-- -----------------------------------------------------------------------------
-- 表: "sys_db_version" (系统基础数据当前增量版本号)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "sys_db_version" IS '系统基础数据当前增量版本号';
COMMENT ON COLUMN "sys_db_version"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "sys_db_version"."version" IS '版本号';
COMMENT ON COLUMN "sys_db_version"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "sys_db_version"."update_time" IS '最后更新时间';

-- -----------------------------------------------------------------------------
-- 表: "sys_param" (系统全局运行参数配置表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "sys_param" IS '系统全局运行参数配置表';
COMMENT ON COLUMN "sys_param"."param_name" IS '系统参数全局唯一键名';
COMMENT ON COLUMN "sys_param"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "sys_param"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "sys_param"."comment" IS '系统参数中文功能描述说明';
COMMENT ON COLUMN "sys_param"."param_value" IS '系统参数配置值内容';

-- -----------------------------------------------------------------------------
-- 表: "update_log" (系统发版与升级日志记录表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "update_log" IS '系统发版与升级日志记录表';
COMMENT ON COLUMN "update_log"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "update_log"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "update_log"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "update_log"."content" IS '内容详情';
COMMENT ON COLUMN "update_log"."time" IS '版本发布升级具体时间';

-- -----------------------------------------------------------------------------
-- 表: "user" (用户主表：存储用户核心账号、VIP订阅、配置与学习概况)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "user" IS '用户主表：存储用户核心账号、VIP订阅、配置与学习概况';
COMMENT ON COLUMN "user"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "user"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "user"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "user"."continuous_daka_day_count" IS '【当前连续打卡天数】基于连续业务日（当地凌晨03:00切换）计算的未中断连续打卡天数（一旦某日断卡未打，即刻断签重置，不同于累计天数）';
COMMENT ON COLUMN "user"."cow_dung" IS '应用内虚拟货币「牛粪」（核心代币，用于小游戏底注、兑换特权及学习激励，非垃圾数据）';
COMMENT ON COLUMN "user"."daka_day_count" IS '【累计打卡天数】历史累计成功完成学习计划并打卡的总天数（只要打过卡就递增，不随断签归零）';
COMMENT ON COLUMN "user"."daka_score" IS '打卡积分';
COMMENT ON COLUMN "user"."email" IS '用户绑定电子邮箱';
COMMENT ON COLUMN "user"."wechat_open_id" IS '微信登录开放平台OpenID';
COMMENT ON COLUMN "user"."wechat_union_id" IS '关联的wechat_union标识ID';
COMMENT ON COLUMN "user"."wechat_nickname" IS '微信授权用户昵称';
COMMENT ON COLUMN "user"."wechat_avatar" IS '微信授权头像URL';
COMMENT ON COLUMN "user"."game_score" IS '小游戏累计战绩得分';
COMMENT ON COLUMN "user"."invite_award_taken" IS '邀请新用户奖励是否已领取 (true/false)';
COMMENT ON COLUMN "user"."is_admin" IS '是否admin标识 (true/false)';
COMMENT ON COLUMN "user"."is_super_admin" IS '是否super_admin标识 (true/false)';
COMMENT ON COLUMN "user"."last_daka_date" IS '【最近成功打卡自然日：0点截断】用户最近一次成功打卡所归属的业务自然日（时分秒截断对齐为 00:00:00）。核心规则：以当地凌晨03:00为分界线，用于严格比对「今日是否已完成打卡」及连续打卡断签计算';
COMMENT ON COLUMN "user"."last_learning_date" IS '【用户最近学习时刻：精确时间戳】用户最近一次产生有效背词/答题动作的物理系统时间戳（精确到毫秒，业务判定时按当地凌晨03:00分界线划归对应的业务自然日）';
COMMENT ON COLUMN "user"."last_login_time" IS '用户最近一次成功登录客户端或服务端的物理时间戳';
COMMENT ON COLUMN "user"."last_share_time" IS '用户最近一次在社交平台完成打卡海报分享的物理时间戳';
COMMENT ON COLUMN "user"."learned_days" IS '【学习活跃天数】累计产生过有效学习背词行为的业务日总数（只要当天学过词即算，通常 >= 累计打卡天数）';
COMMENT ON COLUMN "user"."learning_finished" IS '【今日完成态】当日计划的新词与复习任务是否已全部学完 (true/false，用户点击打卡的前置校验条件)';
COMMENT ON COLUMN "user"."mastered_words" IS '【当前掌握数】当前词库中达到彻底掌握记忆阶梯的词汇总量（受切换词书或手动取消掌握影响，会有波动）';
COMMENT ON COLUMN "user"."max_continuous_daka_day_count" IS '【历史最高连续打卡天数】历史达到的最高连续打卡天数纪录（单调递增，用于防断签后成就丢失、徽章评定及排行榜）';
COMMENT ON COLUMN "user"."nick_name" IS '用户显示昵称';
COMMENT ON COLUMN "user"."password" IS '账号密码哈希';
COMMENT ON COLUMN "user"."throw_dice_chance" IS '掷骰子学习奖励小游戏当前剩余抽奖次数';
COMMENT ON COLUMN "user"."user_name" IS '用户唯一登录账号名';
COMMENT ON COLUMN "user"."words_per_day" IS '【每日计划量】用户当前设置的每日计划学习新词额度（如10/20/30/50个）';
COMMENT ON COLUMN "user"."invited_by_id" IS '邀请人用户ID';
COMMENT ON COLUMN "user"."is_inputor" IS '是否inputor标识 (true/false)';
COMMENT ON COLUMN "user"."is_premium_ios" IS '【苹果IAP独立状态】iOS客户端通过苹果内购订阅判定的是否为活跃会员 (true/false)';
COMMENT ON COLUMN "user"."subscription_expire_date_ios" IS '【苹果IAP独立到期时间】苹果内购自动续费订阅的独立到期时间戳';
COMMENT ON COLUMN "user"."subscription_type_ios" IS '苹果IAP订阅周期类型：monthly(连续包月)/annual(连续包年)';
COMMENT ON COLUMN "user"."subscription_status_ios" IS '苹果IAP订阅实时履约状态：active(生效中)/expired(已到期)/cancelled(已取消续费)';
COMMENT ON COLUMN "user"."last_receipt_data_ios" IS '苹果IAP最新一次内购支付收据原始凭证字符串（用于掉单追溯与苹果二次验证）';
COMMENT ON COLUMN "user"."is_sys_user" IS '是否sys_user标识 (true/false)';
COMMENT ON COLUMN "user"."premium_override_enabled" IS '【人工VIP开关】客服/管理员人工强制赋予会员特权标记（用于客诉纠纷处理、白名单或体验补偿，后台定时任务绝不自动修改此字段）';
COMMENT ON COLUMN "user"."premium_override_update_time" IS '强制会员状态最后修改时间';
COMMENT ON COLUMN "user"."premium_override_reason" IS '人工开启VIP特权的具体业务原因（如：AppStore扣款延迟补偿/内测用户白名单）';
COMMENT ON COLUMN "user"."premium_override_duration" IS '人工VIP特权有效延续时长（形如: 10天/1个月/永久，null表示永久）';
COMMENT ON COLUMN "user"."today_study_started" IS '【今日学习启动标记】今日是否已经点击进入学习界面（用于跨天状态判定与启动动效引导）';
COMMENT ON COLUMN "user"."total_learning_seconds" IS '【历史总学习时长】累计专注学词刷题的总时长（秒）';
COMMENT ON COLUMN "user"."today_learning_seconds" IS '【今日学习时长】当日累计专注学词刷题的有效时长（秒）';
COMMENT ON COLUMN "user"."study_config" IS '【学习偏好JSON】包含每组词数、发音音调、原声例句自动播放等个性化偏好的完整JSON字符串';
COMMENT ON COLUMN "user"."auto_play_sentence" IS '【例句发音开关】展开例句或进入例句学习时是否自动播放原声例句发音 (true/false)';
COMMENT ON COLUMN "user"."show_answers_directly" IS '【快速过词模式】做题时是否直接展示释义与例句，跳过选择题/默写测验 (true/false)';
COMMENT ON COLUMN "user"."auto_play_word" IS '【单词发音开关】切换单词卡片时是否自动朗读单词真人发音 (true/false)';
COMMENT ON COLUMN "user"."enable_all_wrong" IS '【错词深挖模式】是否开启全部错题巩固机制（做错过的词将长期保留在错题集内直至手动移除）';
COMMENT ON COLUMN "user"."asr_pass_rule" IS '【跟读评测规则】口语语音跟读打分判定标准：STRICT(严格)/NORMAL(标准)/LOOSE(宽松)';
COMMENT ON COLUMN "user"."apple_user_id" IS '苹果Sign in with Apple全局唯一标识';
COMMENT ON COLUMN "user"."vip_expire_date" IS '【全渠道通用VIP到期时间】微信、支付宝、华为等通用购买渠道产生的VIP会员截止时间戳';
COMMENT ON COLUMN "user"."vip_type" IS '当前会员类型标识：monthly(月卡)/annual(年卡)/lifetime(终身永久)';
COMMENT ON COLUMN "user"."last_pay_channel" IS '最近一次充值支付渠道：WECHAT(微信)/ALIPAY(支付宝)/APPLE_IAP(苹果)/HUAWEI(华为)';
COMMENT ON COLUMN "user"."max_mastered_words" IS '【历史最高词汇量】历史达到的已掌握词汇量最高峰值记录（全局单调递增，用于成就徽章评定及防止降级）';

-- -----------------------------------------------------------------------------
-- 表: "user_badge" (用户勋章成就表：记录用户已解锁的徽章与获得时间)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "user_badge" IS '用户勋章成就表：记录用户已解锁的徽章与获得时间';
COMMENT ON COLUMN "user_badge"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "user_badge"."user_id" IS '关联的用户ID';
COMMENT ON COLUMN "user_badge"."badge_code" IS '徽章成就全局唯一代号';
COMMENT ON COLUMN "user_badge"."obtain_count" IS 'obtain统计计数值';
COMMENT ON COLUMN "user_badge"."star_level" IS '获得徽章时的星级段位 (1-3星)';
COMMENT ON COLUMN "user_badge"."unlocked_at" IS '徽章点亮解锁时间戳';
COMMENT ON COLUMN "user_badge"."is_equipped" IS '是否equipped标识 (true/false)';
COMMENT ON COLUMN "user_badge"."is_viewed" IS '是否viewed标识 (true/false)';
COMMENT ON COLUMN "user_badge"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "user_badge"."update_time" IS '最后更新时间';

-- -----------------------------------------------------------------------------
-- 表: "user_cow_dung_log" (牛粪（积分/学习货币）流水明细记录表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "user_cow_dung_log" IS '牛粪（积分/学习货币）流水明细记录表';
COMMENT ON COLUMN "user_cow_dung_log"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "user_cow_dung_log"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "user_cow_dung_log"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "user_cow_dung_log"."cow_dung" IS '变动后的牛粪总余额';
COMMENT ON COLUMN "user_cow_dung_log"."delta" IS '本次变动数值增量 (正数增加/负数扣减)';
COMMENT ON COLUMN "user_cow_dung_log"."reason" IS '牛粪流水增减业务事由';
COMMENT ON COLUMN "user_cow_dung_log"."the_time" IS 'the时间戳';
COMMENT ON COLUMN "user_cow_dung_log"."user_id" IS '关联的用户ID';

-- -----------------------------------------------------------------------------
-- 表: "user_db_issue" (用户端云同步冲突与异常日志排查表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "user_db_issue" IS '用户端云同步冲突与异常日志排查表';
COMMENT ON COLUMN "user_db_issue"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "user_db_issue"."user_id" IS '关联的用户ID';
COMMENT ON COLUMN "user_db_issue"."issue_type" IS '端云同步冲突/异常问题分类';
COMMENT ON COLUMN "user_db_issue"."details" IS '同步异常堆栈与诊断现场详情';
COMMENT ON COLUMN "user_db_issue"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "user_db_issue"."update_time" IS '最后更新时间';

-- -----------------------------------------------------------------------------
-- 表: "user_db_log" (客户端与服务端双向增量同步变更日志主表（分区父表）)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "user_db_log" IS '客户端与服务端双向增量同步变更日志主表（分区父表）';
COMMENT ON COLUMN "user_db_log"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "user_db_log"."user_id" IS '关联的用户ID';
COMMENT ON COLUMN "user_db_log"."version" IS '全局单调递增同步流水号（客户端以此序号对比版本拉取增量补丁）';
COMMENT ON COLUMN "user_db_log"."operate" IS '客户端提交的数据变更操作类型：INSERT(新增)/UPDATE(修改)/DELETE(删除)';
COMMENT ON COLUMN "user_db_log"."tbl_name" IS '【单数表名铁律】发生增量变更的目标表名（必须严格与JPA @Table保持完全一致的单数下划线命名，严禁复数如 users）';
COMMENT ON COLUMN "user_db_log"."record_id" IS '【变更主键】被变更记录的主键标识（单主键表为32位UUID；复合主键表为多字段连字符拼接）';
COMMENT ON COLUMN "user_db_log"."record" IS '被变更数据行在变更时刻全量字段的JSON序列化快照内容';
COMMENT ON COLUMN "user_db_log"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "user_db_log"."update_time" IS '最后更新时间';

-- -----------------------------------------------------------------------------
-- 表: "user_db_version" (用户增量同步当前版本号戳)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "user_db_version" IS '用户增量同步当前版本号戳';
COMMENT ON COLUMN "user_db_version"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "user_db_version"."user_id" IS '关联的用户ID';
COMMENT ON COLUMN "user_db_version"."version" IS '版本号';
COMMENT ON COLUMN "user_db_version"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "user_db_version"."update_time" IS '最后更新时间';

-- -----------------------------------------------------------------------------
-- 表: "user_game" (用户小游戏学习参与记录与战绩表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "user_game" IS '用户小游戏学习参与记录与战绩表';
COMMENT ON COLUMN "user_game"."game" IS '参与的具体背单词小游戏标识';
COMMENT ON COLUMN "user_game"."user_id" IS '关联的用户ID';
COMMENT ON COLUMN "user_game"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "user_game"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "user_game"."lose_count" IS 'lose统计计数值';
COMMENT ON COLUMN "user_game"."score" IS '分值/得分';
COMMENT ON COLUMN "user_game"."win_count" IS 'win统计计数值';

-- -----------------------------------------------------------------------------
-- 表: "user_oper" (用户关键敏感操作审计日志表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "user_oper" IS '用户关键敏感操作审计日志表';
COMMENT ON COLUMN "user_oper"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "user_oper"."user_id" IS '关联的用户ID';
COMMENT ON COLUMN "user_oper"."oper_type" IS '用户关键敏感操作类型标识';
COMMENT ON COLUMN "user_oper"."oper_time" IS 'oper时间戳';
COMMENT ON COLUMN "user_oper"."remark" IS '备注说明';
COMMENT ON COLUMN "user_oper"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "user_oper"."update_time" IS '最后更新时间';

-- -----------------------------------------------------------------------------
-- 表: "user_score_log" (用户学分/积分变更历史明细表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "user_score_log" IS '用户学分/积分变更历史明细表';
COMMENT ON COLUMN "user_score_log"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "user_score_log"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "user_score_log"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "user_score_log"."delta" IS '积分变动数值增量 (正增负减)';
COMMENT ON COLUMN "user_score_log"."reason" IS '积分获得或消费业务原因';
COMMENT ON COLUMN "user_score_log"."score" IS '分值/得分';
COMMENT ON COLUMN "user_score_log"."the_time" IS 'the时间戳';
COMMENT ON COLUMN "user_score_log"."user_id" IS '关联的用户ID';

-- -----------------------------------------------------------------------------
-- 表: "user_snapshot_daily" (用户每日学习状态快照备份表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "user_snapshot_daily" IS '用户每日学习状态快照备份表';
COMMENT ON COLUMN "user_snapshot_daily"."the_date" IS '【每日状态快照归属日】用户每日学习进度（牛粪、已学词数、掌握词数等）备份快照归属的业务自然日（时分秒对齐为 00:00:00）';
COMMENT ON COLUMN "user_snapshot_daily"."user_id" IS '关联的用户ID';
COMMENT ON COLUMN "user_snapshot_daily"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "user_snapshot_daily"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "user_snapshot_daily"."cow_dung" IS '快照记录时的牛粪数量';
COMMENT ON COLUMN "user_snapshot_daily"."daka_days" IS '快照记录时的累计打卡天数';
COMMENT ON COLUMN "user_snapshot_daily"."learned_words" IS '快照记录时的已学单词量';
COMMENT ON COLUMN "user_snapshot_daily"."mastered_words" IS '快照记录时的已掌握单词量';
COMMENT ON COLUMN "user_snapshot_daily"."russia_score" IS '快照记录时的俄罗斯方块游戏得分';

-- -----------------------------------------------------------------------------
-- 表: "user_study_daily_stat" (用户每日学词数据聚合统计表（每日新词数、复习数等）)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "user_study_daily_stat" IS '用户每日学词数据聚合统计表（每日新词数、复习数等）';
COMMENT ON COLUMN "user_study_daily_stat"."user_id" IS '关联的用户ID';
COMMENT ON COLUMN "user_study_daily_stat"."date" IS '【每日学习统计业务日：DATE类型】每日学词与做题数据统计汇总归属的业务自然日（以当地凌晨 03:00 为日切分水岭，存储 PostgreSQL 标准 DATE 类型 yyyy-MM-dd）';
COMMENT ON COLUMN "user_study_daily_stat"."study_seconds" IS '当日有效专注学习时长（秒）';
COMMENT ON COLUMN "user_study_daily_stat"."review_count" IS 'review统计计数值';
COMMENT ON COLUMN "user_study_daily_stat"."day_status" IS '当日学习履约状态 (COMPLETED/PARTIAL)';
COMMENT ON COLUMN "user_study_daily_stat"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "user_study_daily_stat"."update_time" IS '最后更新时间';

-- -----------------------------------------------------------------------------
-- 表: "user_study_record" (用户单次做题/学词明细记录表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "user_study_record" IS '用户单次做题/学词明细记录表';
COMMENT ON COLUMN "user_study_record"."the_date" IS '【单次做题流水业务日】单次题目作答明细流水记录归属的业务学习自然日（时分秒对齐为 00:00:00）';
COMMENT ON COLUMN "user_study_record"."user_id" IS '关联的用户ID';
COMMENT ON COLUMN "user_study_record"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "user_study_record"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "user_study_record"."end_time" IS 'end时间戳';
COMMENT ON COLUMN "user_study_record"."start_time" IS 'start时间戳';

-- -----------------------------------------------------------------------------
-- 表: "user_study_step" (用户单词学习步骤状态表：三组单表记录用户在各组内的打卡与阶段步骤状态)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "user_study_step" IS '用户单词学习步骤状态表：三组单表记录用户在各组内的打卡与阶段步骤状态';
COMMENT ON COLUMN "user_study_step"."study_step" IS '该小分组当前正在执行的具体艾宾浩斯复习阶梯编号 (0-7)';
COMMENT ON COLUMN "user_study_step"."user_id" IS '关联的用户ID';
COMMENT ON COLUMN "user_study_step"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "user_study_step"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "user_study_step"."seq" IS '本学习步骤在组内的顺序号，从0开始';
COMMENT ON COLUMN "user_study_step"."state" IS '该学习步骤当前执行状态 (WAITING/DOING/FINISHED)';
COMMENT ON COLUMN "user_study_step"."scope" IS '业务学习流程作用域：LEARNING(每日核心学习流程) / REVIEW(日常复习巩固流程)';
COMMENT ON COLUMN "user_study_step"."group_name" IS '''check'' 测评 / ''correct'' 答对后 / ''wrong'' 答错后（只读镜像，主键组件见 id）';

-- -----------------------------------------------------------------------------
-- 表: "user_wrong_word" (用户错题本：记录做错的单词及错误次数与最后出错时间)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "user_wrong_word" IS '用户错题本：记录做错的单词及错误次数与最后出错时间';
COMMENT ON COLUMN "user_wrong_word"."user_id" IS '关联的用户ID';
COMMENT ON COLUMN "user_wrong_word"."word_id" IS '关联的单词ID';
COMMENT ON COLUMN "user_wrong_word"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "user_wrong_word"."update_time" IS '最后更新时间';

-- -----------------------------------------------------------------------------
-- 表: "verb_tense" (动词时态与词形变体表：记录原型、过去式、过去分词、现在分词、第三人称单数)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "verb_tense" IS '动词时态与词形变体表：记录原型、过去式、过去分词、现在分词、第三人称单数';
COMMENT ON COLUMN "verb_tense"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "verb_tense"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "verb_tense"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "verb_tense"."tense_type" IS '时态的类型 - ORDR_PMTR';
COMMENT ON COLUMN "verb_tense"."tensed_spell" IS '动词变换后的变体拼写字符串';
COMMENT ON COLUMN "verb_tense"."word_id" IS '关联的单词ID';

-- -----------------------------------------------------------------------------
-- 表: "wechat_auth_event" (微信开放平台授权变更合规事件记录表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "wechat_auth_event" IS '微信开放平台授权变更合规事件记录表';
COMMENT ON COLUMN "wechat_auth_event"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "wechat_auth_event"."app_id" IS '事件所属的移动应用 AppID';
COMMENT ON COLUMN "wechat_auth_event"."event" IS '事件类型: user_authorization_revoke(撤回) / user_info_modified(资料变更) / user_authorization_cancellation(注销)';
COMMENT ON COLUMN "wechat_auth_event"."open_id" IS '授权用户的 OpenID';
COMMENT ON COLUMN "wechat_auth_event"."union_id" IS '授权用户的 UnionID';
COMMENT ON COLUMN "wechat_auth_event"."revoke_info" IS '用户撤回的授权信息。移动应用固定为 301（撤回所有授权信息）';
COMMENT ON COLUMN "wechat_auth_event"."event_time" IS '事件发生时间（微信 CreateTime）';
COMMENT ON COLUMN "wechat_auth_event"."raw_payload" IS '解密后的完整事件报文，用于审计与排障';
COMMENT ON COLUMN "wechat_auth_event"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "wechat_auth_event"."update_time" IS '最后更新时间';

-- -----------------------------------------------------------------------------
-- 表: "word" (单词主表：存储单词拼写、音标、热度排序及基础属性)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "word" IS '单词主表：存储单词拼写、音标、热度排序及基础属性';
COMMENT ON COLUMN "word"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "word"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "word"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "word"."america_pronounce" IS '美式国际音标 (KK音标标准)';
COMMENT ON COLUMN "word"."british_pronounce" IS '英式国际音标 (DJ音标标准)';
COMMENT ON COLUMN "word"."group_info" IS '单词所属的大纲分组信息';
COMMENT ON COLUMN "word"."long_desc" IS '单词的详细描述';
COMMENT ON COLUMN "word"."popularity" IS '【注意排序方向】单词核心词频热度排序值（数值越小代表越常用高频，如1为全语言最核心词；数值越大代表越生僻罕见）';
COMMENT ON COLUMN "word"."pronounce" IS '国际音标英美通用标注文本';
COMMENT ON COLUMN "word"."short_desc" IS '单词的简要描述';
COMMENT ON COLUMN "word"."spell" IS '单词英文拼写';
COMMENT ON COLUMN "word"."is_updating" IS '是否updating标识 (true/false)';
COMMENT ON COLUMN "word"."embedding_1bit" IS '2048维1-bit二值化压缩语义向量（用于前端极速位运算汉明距离做相似词聚类与语义推荐）';

-- -----------------------------------------------------------------------------
-- 表: "word_additional_info" (单词附加助记信息表：构词法、词根词缀、趣味助记技巧)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "word_additional_info" IS '单词附加助记信息表：构词法、词根词缀、趣味助记技巧';
COMMENT ON COLUMN "word_additional_info"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "word_additional_info"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "word_additional_info"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "word_additional_info"."content" IS '内容详情';
COMMENT ON COLUMN "word_additional_info"."foot_count" IS 'foot统计计数值';
COMMENT ON COLUMN "word_additional_info"."hand_count" IS 'hand统计计数值';
COMMENT ON COLUMN "word_additional_info"."user_id" IS '关联的用户ID';
COMMENT ON COLUMN "word_additional_info"."word_id" IS '关联的单词ID';

-- -----------------------------------------------------------------------------
-- 表: "word_core_image" (一词多义核心意象与AI生图拓扑表：存储DeepSeek提炼的核心意象及火山引擎生图数据)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "word_core_image" IS '一词多义核心意象与AI生图拓扑表：存储DeepSeek提炼的核心意象及火山引擎生图数据';
COMMENT ON COLUMN "word_core_image"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "word_core_image"."word_id" IS '关联的单词ID';
COMMENT ON COLUMN "word_core_image"."word" IS '单词拼写';
COMMENT ON COLUMN "word_core_image"."is_applicable" IS '【大模型认知判定】是否适合提取一词多义核心意象（true:存在多重引申与底层物理图式；false:单一实物名词或生僻专有名词）';
COMMENT ON COLUMN "word_core_image"."not_applicable_reason" IS '不适合提取核心意象时的具体原因说明（如: 单一具体实物名词，无隐喻空间）';
COMMENT ON COLUMN "word_core_image"."core_image" IS '【底层意象短语】4-10字核心意象短语（脱离单词表面具体释义，表达底层的物理拓扑或动力学机制，如 charge -> 充填装载）';
COMMENT ON COLUMN "word_core_image"."schema_desc" IS '【认知图式剖析】认知语言学与词源学深度图式剖析说明（解释核心意象如何引申演化出各个具体词义）';
COMMENT ON COLUMN "word_core_image"."topology_json" IS '【拓扑关系网络】核心意象与各派生词义分支之间的演化图式拓扑关系结构化JSON';
COMMENT ON COLUMN "word_core_image"."image_prompt" IS '【文生图提示词】驱动文生图大模型生成2D极简认知图式简笔画的纯中文精确提示词（严禁包含英文字母）';
COMMENT ON COLUMN "word_core_image"."image_url" IS '生成的2D极简认知语言学图式矢量简笔画持久化图片URL';
COMMENT ON COLUMN "word_core_image"."image_status" IS '生图任务执行状态：SUCCESS(成功)/FAILED(失败)/PENDING(等待中)/SKIPPED(跳过不生图)';
COMMENT ON COLUMN "word_core_image"."image_model" IS '使用的文生图大底座模型标识（如 doubao-seed-image-3.0）';
COMMENT ON COLUMN "word_core_image"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "word_core_image"."update_time" IS '最后更新时间';

-- -----------------------------------------------------------------------------
-- 表: "word_embedding" (单词语义嵌入向量表：存储2048维1-bit或浮点向量，用于相似词与聚类推荐)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "word_embedding" IS '单词语义嵌入向量表：存储2048维1-bit或浮点向量，用于相似词与聚类推荐';
COMMENT ON COLUMN "word_embedding"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "word_embedding"."embedding" IS '浮点或稠密语义向量序列化文本';
COMMENT ON COLUMN "word_embedding"."dimension" IS '向量维度数 (如 1024, 2048)';
COMMENT ON COLUMN "word_embedding"."model_name" IS '生成向量的大模型名称 (如 text-embedding-v3)';
COMMENT ON COLUMN "word_embedding"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "word_embedding"."create_time" IS '记录创建时间';

-- -----------------------------------------------------------------------------
-- 表: "word_image" (单词图解插图表：人工或系统为单词配置的辅助记忆图解)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "word_image" IS '单词图解插图表：人工或系统为单词配置的辅助记忆图解';
COMMENT ON COLUMN "word_image"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "word_image"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "word_image"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "word_image"."foot" IS '【历史命名注意】审核结论标记（1:审核通过正式发布展示给用户, 0:待人工/AI审核, -1:已驳回隐藏，非足迹）';
COMMENT ON COLUMN "word_image"."hand" IS '【历史命名注意】用户社区点赞/认同支持累计计数（借用举手之意，非手势数据）';
COMMENT ON COLUMN "word_image"."image_file" IS '单词图解插图文件相对路径或OSS对象键名';
COMMENT ON COLUMN "word_image"."author_id" IS '插图上传制作人用户ID';
COMMENT ON COLUMN "word_image"."word_id" IS '关联的单词ID';
COMMENT ON COLUMN "word_image"."status" IS '状态标识';
COMMENT ON COLUMN "word_image"."audit_reason" IS '人工或大模型审核通过/驳回的具体原因说明';
COMMENT ON COLUMN "word_image"."owner_id" IS '插图数据归属人ID';

-- -----------------------------------------------------------------------------
-- 表: "word_sentence" (单词与例句关联表：记录单词在哪些例句中出现及匹配词形)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "word_sentence" IS '单词与例句关联表：记录单词在哪些例句中出现及匹配词形';
COMMENT ON COLUMN "word_sentence"."sentence_id" IS '关联的例句ID';
COMMENT ON COLUMN "word_sentence"."word_id" IS '关联的单词ID';
COMMENT ON COLUMN "word_sentence"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "word_sentence"."update_time" IS '最后更新时间';

-- -----------------------------------------------------------------------------
-- 表: "word_shortdesc_chinese" (单词快速中文简释缓存表)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE "word_shortdesc_chinese" IS '单词快速中文简释缓存表';
COMMENT ON COLUMN "word_shortdesc_chinese"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "word_shortdesc_chinese"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "word_shortdesc_chinese"."update_time" IS '最后更新时间';
COMMENT ON COLUMN "word_shortdesc_chinese"."content" IS '内容详情';
COMMENT ON COLUMN "word_shortdesc_chinese"."foot" IS '【历史命名注意】简释审核结论标记（1:审核通过正式生效, 0:待审核, -1:驳回隐藏）';
COMMENT ON COLUMN "word_shortdesc_chinese"."hand" IS '【历史命名注意】用户对该中文简释的点赞支持累计计数';
COMMENT ON COLUMN "word_shortdesc_chinese"."author_id" IS '简释录入者用户ID';
COMMENT ON COLUMN "word_shortdesc_chinese"."word_id" IS '关联的单词ID';
COMMENT ON COLUMN "word_shortdesc_chinese"."owner_id" IS '简释数据归属人ID';
