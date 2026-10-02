package beidanci.service.bo;

import java.io.File;
import java.util.*;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.*;
import beidanci.service.dao.UserDbVersionDao;
import beidanci.service.po.*;
import beidanci.util.Constants;
import beidanci.service.util.JsonUtils;
import beidanci.service.util.MyImage;
import beidanci.service.util.Util;
import beidanci.service.util.SysParamUtil;

/**
 * 系统健康检查业务逻辑
 */
@Service
public class SystemHealthCheckBo {
    private static final org.slf4j.Logger logger = org.slf4j.LoggerFactory.getLogger(SystemHealthCheckBo.class);

    @Autowired
    private DictBo dictBo;
    
    
    @Autowired
    private UserDbVersionDao userDbVersionDao;
    
    @Autowired
    private MeaningItemBo meaningItemBo;
    
    @Autowired
    private SentenceBo sentenceBo;
    
    @Autowired
    private UserBo userBo;
    
    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @Autowired
    private WordBo wordBo;

    @Autowired
    private UserDbSyncBo userDbSyncBo;

    @Autowired
    private AiBo aiBo;

    @Autowired
    private SysDbSyncBo sysDbSyncBo;

    @Autowired
    private DictWordBo dictWordBo;

    @Autowired
    private WordImageBo wordImageBo;

    @Autowired
    private SysParamUtil sysParamUtil;

    @Autowired
    private LearningWordBo learningWordBo;

    @Autowired
    private SysErrorBo sysErrorBo;

    /**
     * 检查系统词典完整性
     */
    public SystemHealthCheckResult checkSystemDictIntegrity() {
        List<SystemHealthIssue> issues = new ArrayList<>();
        List<String> errors = new ArrayList<>();
        
        try {
            // 获取所有系统词典（ownerId = 15118）
            List<String> systemDictIds = dictBo.getSystemDictIds();
            
            for (String dictId : systemDictIds) {
                // 检查词典单词序号连续性
                checkDictWordSequence(dictId, issues);
                
                // 检查词典单词数量一致性
                checkDictWordCount(dictId, issues);
            }
            
        } catch (Exception e) {
            errors.add("检查系统词典完整性时出错: " + e.getMessage());
        }
        
        return new SystemHealthCheckResult(issues.isEmpty() && errors.isEmpty(), issues, errors);
    }

    /**
     * 检查用户词典完整性
     */
    public SystemHealthCheckResult checkUserDictIntegrity() {
        List<SystemHealthIssue> issues = new ArrayList<>();
        List<String> errors = new ArrayList<>();
        
        try {
            // 使用原生SQL一次性获取所有用户词典信息，参考check_db.py的高效查询
            String sql = "SELECT d.id, d.name, d.owner_id, d.word_count, d.base_dict_id, d.create_time " +
                        "FROM dict d " +
                        "WHERE d.visible = 1 AND d.is_ready = 1 AND d.owner_id != :sysUserId " +
                        "ORDER BY d.create_time DESC";
            
            MapSqlParameterSource params = new MapSqlParameterSource("sysUserId", Constants.SYS_USER_SYS_ID);
            List<Object[]> dicts = namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> 
                new Object[]{
                    rs.getString("id"),
                    rs.getString("name"),
                    rs.getString("owner_id"),
                    rs.getObject("wordCount", Integer.class),
                    rs.getString("base_dict_id")
                }
            );
            
            for (Object[] dict : dicts) {
                String dictId = (String) dict[0];
                String dictName = (String) dict[1];
                String ownerId = (String) dict[2];
                Integer wordCount = (Integer) dict[3];
                String baseDictId = (String) dict[4];
                
                // 检查词典单词序号连续性和数量一致性
                checkDictWordSequenceAndCount(dictId, dictName, ownerId, wordCount, baseDictId, issues);
            }
            
        } catch (DataAccessException e) {
            errors.add("检查用户词典完整性时出错: " + e.getMessage());
        }
        
        return new SystemHealthCheckResult(issues.isEmpty() && errors.isEmpty(), issues, errors);
    }

    

    /** 一次审计最多返回多少条不一致明细，避免明细过多把响应撑爆 */
    private static final int LEARNING_PROGRESS_AUDIT_LIMIT = 200;

    /** 审计窗口只回看最近这么久，兜住异常的 last_learning_date（epoch 或超前写入） */
    private static final int LEARNING_PROGRESS_AUDIT_MAX_LOOKBACK_HOURS = 72;

    /**
     * 检查「今日环节进度」与「今日评分流水」是否自洽（只读，不修任何数据）。
     *
     * <p>判定两条不变式：
     * <ol>
     * <li>今天某词的学习记录条数 &lt;= 该词记录的今日环节进度（today_learned_times）。
     * 条数多出来说明同一次作答被重复计分。</li>
     * <li>今日环节进度 &lt;= 该用户当前配置下的轨道长度上限。进度超过上限说明环节被多推进了，
     * 客户端会把越界的环节编号夹回最后一个环节，于是该词会带着「答案已揭晓」的界面状态被重复出题，
     * 这正是用户反馈「答对了却卡住、只能强行切走」的成因。</li>
     * </ol>
     *
     * <p>两条都成立时数据自洽。第 2 条取「新词轨道」与「复习轨道」中较长的一条作上限：
     * 只要进度超过了两条中更长的那个，无论该词今天走哪条轨道都必然是越界的，不会误报。
     *
     * <p>「今天」的窗口按用户自己的学习时刻锚定：取该用户最近一条学习记录的写入时刻往前 24 小时。
     * 不用固定回看 36 小时，那样会把更早一个业务日的流水算进「今天」；
     * 而评分流水的 create_time 由服务端写入，无法直接换算各用户的当地业务日。
     *
     * <p><b>只审计「今日环节进度 &gt; 0」的词</b>：进度为 0、窗口内却查到流水，绝大多数是
     * 用户上一个业务日学过、客户端的跨天复位已把进度清零（实测这类占了八成的告警），
     * 属于正常状态、不是缺陷。已知盲点：若某个词的进度被复位成 0 之后又有重复计分，
     * 这种"差一条记录"的不对称本项不会再报出来；需要时按同一个用户锚定窗口手工核对
     * learning_word.today_learned_times 与 learning_log 的条数即可。
     */
    public SystemHealthCheckResult checkLearningProgressConsistency() {
        List<SystemHealthIssue> issues = new ArrayList<>();
        List<String> errors = new ArrayList<>();

        try {
            String sql = "SELECT l.user_id, u.nick_name, l.word_id, w.spell, "
                    + "       count(*) AS today_log_count, lw.today_learned_times, lw.update_time, "
                    + "       GREATEST(COALESCE(nullif(new_max.max_len, 0), 0), "
                    + "                COALESCE(nullif(rev_max.max_len, 0), 0)) AS track_len_max "
                    + "FROM learning_log l "
                    + "JOIN learning_word lw ON lw.user_id = l.user_id AND lw.word_id = l.word_id "
                    + "LEFT JOIN \"user\" u ON u.id = l.user_id "
                    + "LEFT JOIN word w ON w.id = l.word_id "
                    + "JOIN (SELECT user_id, MAX(create_time) AS anchor FROM learning_log GROUP BY user_id) a "
                    + "  ON a.user_id = l.user_id "
                    + "LEFT JOIN ( "
                    + "    SELECT user_id, MAX(check_len + correct_len + wrong_len) AS max_len "
                    + "    FROM ( "
                    + "        SELECT user_id, "
                    + "               MAX(CASE WHEN group_name = 'check' THEN 1 ELSE 0 END) AS check_len, "
                    + "               SUM(CASE WHEN group_name = 'correct' THEN 1 ELSE 0 END) AS correct_len, "
                    + "               SUM(CASE WHEN group_name = 'wrong' THEN 1 ELSE 0 END) AS wrong_len "
                    + "        FROM user_study_step "
                    + "        WHERE scope = 'new' AND state = 'Active' "
                    + "        GROUP BY user_id "
                    + "    ) t GROUP BY user_id "
                    + ") new_max ON new_max.user_id = l.user_id "
                    + "LEFT JOIN ( "
                    + "    SELECT user_id, MAX(check_len + correct_len + wrong_len) AS max_len "
                    + "    FROM ( "
                    + "        SELECT user_id, "
                    + "               MAX(CASE WHEN group_name = 'check' THEN 1 ELSE 0 END) AS check_len, "
                    + "               SUM(CASE WHEN group_name = 'correct' THEN 1 ELSE 0 END) AS correct_len, "
                    + "               SUM(CASE WHEN group_name = 'wrong' THEN 1 ELSE 0 END) AS wrong_len "
                    + "        FROM user_study_step "
                    + "        WHERE scope = 'review' AND state = 'Active' "
                    + "        GROUP BY user_id "
                    + "    ) t GROUP BY user_id "
                    + ") rev_max ON rev_max.user_id = l.user_id "
                    + "WHERE l.create_time >= a.anchor - make_interval(hours => 24) "
                    + "  AND l.create_time >= now() - make_interval(hours => :maxLookbackHours) "
                    + "GROUP BY l.user_id, u.nick_name, l.word_id, w.spell, lw.today_learned_times, "
                    + "         lw.update_time, new_max.max_len, rev_max.max_len "
                    + "HAVING lw.today_learned_times > 0 AND (count(*) > lw.today_learned_times "
                    + "    OR lw.today_learned_times > "
                    + "       GREATEST(COALESCE(new_max.max_len, 0), COALESCE(rev_max.max_len, 0))) "
                    + "ORDER BY count(*) - lw.today_learned_times DESC, l.user_id, l.word_id "
                    + "LIMIT :auditLimit";

            MapSqlParameterSource params = new MapSqlParameterSource()
                    .addValue("maxLookbackHours", LEARNING_PROGRESS_AUDIT_MAX_LOOKBACK_HOURS)
                    .addValue("auditLimit", LEARNING_PROGRESS_AUDIT_LIMIT);

            // 一次扫描同时产出"给人看的说明"与"给界面用的可修性明细"：
            // 后者让管理后台能逐词修复，不用为同一件事再扫一遍全量
            List<SystemHealthIssue> found = new ArrayList<>();
            List<LearningProgressRepairItem> repairs = new ArrayList<>();
            namedParameterJdbcTemplate.query(sql, params, rs -> {
                String userId = rs.getString("user_id");
                String nickName = rs.getString("nick_name");
                String wordId = rs.getString("word_id");
                String spell = rs.getString("spell");
                int todayLogCount = rs.getInt("today_log_count");
                int todayLearnedTimes = rs.getInt("today_learned_times");
                int trackLenMax = rs.getInt("track_len_max");
                found.add(buildLearningProgressIssue(userId, nickName, wordId, spell,
                        todayLogCount, todayLearnedTimes, trackLenMax));
                repairs.add(buildLearningProgressRepairItem(userId, nickName, wordId, spell,
                        todayLearnedTimes, todayLogCount, trackLenMax, rs.getTimestamp("update_time")));
            });

            issues.addAll(found);
            return new SystemHealthCheckResult(issues.isEmpty() && errors.isEmpty(), issues, errors, repairs);
        } catch (DataAccessException e) {
            errors.add("检查学习进度与学习记录一致性时出错: " + e.getMessage());
        }

        return new SystemHealthCheckResult(issues.isEmpty() && errors.isEmpty(), issues, errors);
    }

    /** 进度行"多久没被更新过"才允许服务端改动：这段时间内用户显然没有在学这个词 */
    static final int REPAIR_MIN_STALE_HOURS = 6;

    /** 服务端修复"今日环节进度"后，写入 sys_error 的审计分类 */
    static final String ADMIN_REPAIRED_PROGRESS_ERROR_TYPE = "ADMIN_REPAIRED_PROGRESS";

    /**
     * 管理端单点修复：把某个词"今天的环节进度"改回今天的评分流水条数。
     *
     * <p>这是**服务端主动改用户数据**，走的是与打卡补全同一套下行机制
     * （{@link UserDbSyncBo#logUserOperation} 写 user_db_log 并递增 user_db_version），
     * 因此用户下次同步时能自动拿到修正值。注意：同步是"客户端权威"，
     * 若他本地还有未上行的旧值，下次上行会把它覆盖回来，修复因此可能失效——
     * 所以这里会先把现场写进 sys_error 留痕，即便后来被覆盖也查得到发生过什么。
     *
     * @param operatorUserId 执行修复的管理员，只用于审计留痕，可为空
     */
    @Transactional(rollbackFor = Throwable.class)
    public LearningProgressRepairItem repairLearningProgress(String userId, String wordId, String operatorUserId) {
        if (userId == null || userId.trim().isEmpty() || wordId == null || wordId.trim().isEmpty()) {
            return null;
        }
        LearningWord learningWord = learningWordBo.findById(new LearningWordId(userId, wordId));
        if (learningWord == null) {
            return new LearningProgressRepairItem(userId, null, wordId, wordId, null, null, null,
                    false, LearningProgressRepairItem.BLOCK_NOT_FOUND);
        }

        final int progress = learningWord.getTodayLearnedTimes() == null ? 0 : learningWord.getTodayLearnedTimes();
        // 目标值 = 今天真实的评分流水条数（复用体检里那把"业务日窗口"，避免此处另造一套口径）
        final int target = countTodayLogs(userId, wordId);

        LearningProgressRepairItem judgement = buildLearningProgressRepairItem(userId, null, wordId,
                wordId, progress, target, trackLenMaxOf(userId), learningWord.getUpdateTime());
        if (!judgement.getCanRepair()) {
            return judgement;
        }

        learningWord.setTodayLearnedTimes(target);
        try {
            learningWordBo.updateEntity(learningWord);
        } catch (IllegalAccessException e) {
            throw new RuntimeException("更新学习进度失败: userId=" + userId + ", wordId=" + wordId, e);
        }

        // 写下行日志并递增用户数据版本号，用户下次同步即可自动拉到这次修正
        String operator = operatorUserId;
        User operatorUser = operatorUserId == null ? null : userBo.findById(operatorUserId);
        if (operatorUser != null) {
            operator = (operatorUser.getNickName() == null || operatorUser.getNickName().isEmpty())
                    ? operatorUser.getUserName()
                    : operatorUser.getNickName();
        }
        String recordJson = JsonUtils.toJson(learningWord.swallowToDto());
        userDbSyncBo.logUserOperation(userId, "learning_word", "UPDATE",
                userId + "-" + wordId, recordJson);

        // 审计留痕：谁、在什么时候、把哪个词从多少改成了多少
        try {
            sysErrorBo.recordError(operatorUserId, ADMIN_REPAIRED_PROGRESS_ERROR_TYPE,
                    "管理员「" + (operator == null ? "未知" : operator) + "」修复了学习进度：\n"
                            + "用户=" + userId + "\n"
                            + "单词=" + wordId + "\n"
                            + "今日环节进度: " + progress + " -> " + target + "\n"
                            + "今日评分流水条数=" + target + "\n"
                            + "说明: 服务端单点修复（只下调进度、未改动任何学习记录），"
                            + "已写入 learning_word 下行同步日志并递增用户数据版本号",
                    null, null);
            logger.info("🛠️ [ADMIN_REPAIR] 修复学习进度: userId={}, wordId={}, progress {} -> {}, operator={}",
                    userId, wordId, progress, target, operatorUserId);
        } catch (IllegalAccessException e) {
            // 审计失败不影响修复本身：修复已完成且日志已下发，只记服务端日志
            logger.error("写入学习进度修复审计失败: userId=" + userId + ", wordId=" + wordId, e);
        }

        return new LearningProgressRepairItem(userId, null, wordId, wordId,
                progress, target, judgement.getTrackLenMax(), true, null);
    }

    /** 某词今天（当地业务日窗口）的评分流水条数；与客户端、体检页用的是同一把窗口 */
    private int countTodayLogs(String userId, String wordId) {
        String sql = "SELECT count(*) FROM learning_log l "
                + "JOIN (SELECT MAX(create_time) AS anchor FROM learning_log WHERE user_id = :userId) a ON 1=1 "
                + "WHERE l.user_id = :userId AND l.word_id = :wordId "
                + "  AND l.create_time >= a.anchor - make_interval(hours => 24) "
                + "  AND l.create_time >= now() - make_interval(hours => :maxLookbackHours)";
        MapSqlParameterSource params = new MapSqlParameterSource()
                .addValue("userId", userId)
                .addValue("wordId", wordId)
                .addValue("maxLookbackHours", LEARNING_PROGRESS_AUDIT_MAX_LOOKBACK_HOURS);
        Integer count = namedParameterJdbcTemplate.queryForObject(sql, params, Integer.class);
        return count == null ? 0 : count;
    }

    /** 该用户当前配置下轨道长度上限（新词/复习取更长的一条） */
    private int trackLenMaxOf(String userId) {
        String sql = "SELECT GREATEST("
                + "  COALESCE((SELECT MAX(check_len + correct_len + wrong_len) FROM ("
                + "      SELECT MAX(CASE WHEN group_name = 'check' THEN 1 ELSE 0 END) AS check_len,"
                + "             SUM(CASE WHEN group_name = 'correct' THEN 1 ELSE 0 END) AS correct_len,"
                + "             SUM(CASE WHEN group_name = 'wrong' THEN 1 ELSE 0 END) AS wrong_len"
                + "      FROM user_study_step WHERE user_id = :userId AND scope = 'new' AND state = 'Active'"
                + "      GROUP BY user_id) t), 0),"
                + "  COALESCE((SELECT MAX(check_len + correct_len + wrong_len) FROM ("
                + "      SELECT MAX(CASE WHEN group_name = 'check' THEN 1 ELSE 0 END) AS check_len,"
                + "             SUM(CASE WHEN group_name = 'correct' THEN 1 ELSE 0 END) AS correct_len,"
                + "             SUM(CASE WHEN group_name = 'wrong' THEN 1 ELSE 0 END) AS wrong_len"
                + "      FROM user_study_step WHERE user_id = :userId AND scope = 'review' AND state = 'Active'"
                + "      GROUP BY user_id) t), 0)"
                + ")";
        MapSqlParameterSource params = new MapSqlParameterSource("userId", userId);
        Integer maxLen = namedParameterJdbcTemplate.queryForObject(sql, params, Integer.class);
        return maxLen == null ? 0 : maxLen;
    }

    /**
     * 判定某个词是否可以在服务端单点修复，并给出原因。
     *
     * <p>四条护栏缺一不可：
     * <ol>
     * <li>进度必须真的超过轨道长度 —— 说明该词今天已经把整条轨道走完、多出来的那一格是重复推进。
     * 只"比流水多一条"但没超轨道长度的，很可能是同步滞后，不动。</li>
     * <li>今天必须有评分流水 —— 否则没有可靠依据判断该整成几。</li>
     * <li>目标值必须小于当前值 —— 只下调，绝不把进度往上补。</li>
     * <li>进度行必须已经"凉"了（{@value #REPAIR_MIN_STALE_HOURS} 小时内没被更新过）——
     * 用户可能正在学这个词，改它会倒退他刚走完的进度。</li>
     * </ol>
     */
    static LearningProgressRepairItem buildLearningProgressRepairItem(String userId, String nickName,
            String wordId, String spell, int progress, int todayLogCount, int trackLenMax, Date lastProgressUpdate) {
        String target = (spell == null || spell.isEmpty()) ? wordId : spell;
        String blockReason = null;
        if (progress <= trackLenMax) {
            blockReason = LearningProgressRepairItem.BLOCK_NOT_OVER_TRACK;
        } else if (todayLogCount <= 0) {
            blockReason = LearningProgressRepairItem.BLOCK_NO_LOG_TODAY;
        } else if (progress <= todayLogCount) {
            blockReason = LearningProgressRepairItem.BLOCK_NOT_OVER_TRACK;
        } else if (lastProgressUpdate != null
                && lastProgressUpdate.after(new Date(System.currentTimeMillis()
                        - REPAIR_MIN_STALE_HOURS * 3600_000L))) {
            blockReason = LearningProgressRepairItem.BLOCK_UPDATED_TODAY;
        }
        return new LearningProgressRepairItem(userId, nickName, wordId, target,
                progress, todayLogCount, trackLenMax, blockReason == null, blockReason);
    }

    /**
     * 把一条审计结果整理成给人看的说明。只表达「哪里对不上」，不做任何修复判断。
     * 抽出静态方法是为了让判定口径可被单元测试直接覆盖。
     */
    static SystemHealthIssue buildLearningProgressIssue(String userId, String nickName, String wordId,
            String spell, int todayLogCount, int todayLearnedTimes, int trackLenMax) {
        String wordLabel = (spell == null || spell.isEmpty()) ? wordId : spell;
        StringBuilder desc = new StringBuilder();
        desc.append("用户「").append(nickName == null || nickName.isEmpty() ? userId : nickName)
                .append("」(").append(userId).append(") 的单词 ").append(wordLabel)
                .append(" (").append(wordId).append(")：今日评分流水 ")
                .append(todayLogCount).append(" 条，记录的今日环节进度 ")
                .append(todayLearnedTimes).append("，当前配置下轨道长度上限 ")
                .append(trackLenMax);
        if (todayLogCount > todayLearnedTimes) {
            desc.append("。评分流水多于今日进度，说明同一次作答被重复写了学习记录");
        }
        if (todayLearnedTimes > todayLogCount) {
            desc.append("。今日进度多于评分流水，说明同一次作答被重复推进了环节，"
                    + "该词会被夹在最后一个环节反复出题、答案揭晓后没有可前进的出口");
        }
        if (todayLearnedTimes > trackLenMax) {
            desc.append("。进度超过轨道长度，环节被多推进");
        }
        return new SystemHealthIssue("learning_progress_inconsistent", desc.toString(),
                "learning_progress_inconsistent");
    }

    /**
     * 检查数据库版本一致性
     */
    public SystemHealthCheckResult checkDbVersionConsistency() {
        List<SystemHealthIssue> issues = new ArrayList<>();
        List<String> errors = new ArrayList<>();
        
        try {
            // 获取所有用户的当前数据库版本
            List<Object[]> userVersions = userDbVersionDao.getAllUserVersions();
            
            for (Object[] userVersion : userVersions) {
                String userId = (String) userVersion[0];
                Integer currentVersion = (Integer) userVersion[1];
                
                // 检查是否有版本号大于当前版本的日志
                int invalidLogCount = userDbVersionDao.countInvalidLogs(userId, currentVersion);
                
                if (invalidLogCount > 0) {
                    issues.add(new SystemHealthIssue(
                        "版本号异常",
                        String.format("用户 %s 有 %d 条版本号异常的日志", userId, invalidLogCount),
                        "db_version"
                    ));
                }
            }
            
        } catch (Exception e) {
            errors.add("检查数据库版本一致性时出错: " + e.getMessage());
        }
        
        return new SystemHealthCheckResult(issues.isEmpty() && errors.isEmpty(), issues, errors);
    }

    /**
     * 检查通用词典完整性
     */
    public SystemHealthCheckResult checkCommonDictIntegrity() {
        List<SystemHealthIssue> issues = new ArrayList<>();
        List<String> errors = new ArrayList<>();
        
        try {
            // 检查通用词典（id='0'）的完整性
            String commonDictId = "0";
            
            // 检查是否有释义项
            List<String> wordsWithoutMeanings = meaningItemBo.findWordsWithoutMeanings(commonDictId);
            for (String wordId : wordsWithoutMeanings) {
                Word word = wordBo.findById(wordId);
                String wordDesc = (word != null && word.getSpell() != null) ? word.getSpell() : wordId;
                issues.add(new SystemHealthIssue(
                    "通用词典不完整",
                    "单词 " + wordDesc + " 缺少释义项",
                    "common_dict_integrity"
                ));
            }
            
            // 检查释义项是否有例句
            List<String> meaningsWithoutSentences = sentenceBo.findMeaningsWithoutSentences(commonDictId);
            for (String meaningId : meaningsWithoutSentences) {
                issues.add(new SystemHealthIssue(
                    "通用词典不完整",
                    "释义项 " + meaningId + " 缺少例句",
                    "common_dict_integrity"
                ));
            }

            // 检查单词数量一致性
            checkDictWordCount(commonDictId, issues);
            
        } catch (Exception e) {
            errors.add("检查通用词典完整性时出错: " + e.getMessage());
        }
        
        return new SystemHealthCheckResult(issues.isEmpty() && errors.isEmpty(), issues, errors);
    }

    /**
     * 检查系统词典是否缺失通用词库（0库）物理托底数据
     */
    public SystemHealthCheckResult checkSystemDictMissingFallback() {
        List<SystemHealthIssue> issues = new ArrayList<>();
        List<String> errors = new ArrayList<>();
        
        try {
            String sql = "SELECT COUNT(DISTINCT word_id) FROM dict_word WHERE word_id NOT IN (SELECT word_id FROM dict_word WHERE dict_id = '0')";
            Integer missingCount = namedParameterJdbcTemplate.queryForObject(sql, new MapSqlParameterSource(), Integer.class);
            if (missingCount != null && missingCount > 0) {
                issues.add(new SystemHealthIssue(
                    "底层通用词库缺失托底数据",
                    String.format("管理后台查出有 %d 个在用单词物理脱离了基础的0库记录，这会影响新下发的数据完整性，请立即修复。", missingCount),
                    "sys_dict_missing_fallback"
                ));
            }
        } catch (Exception e) {
            errors.add("检查底层托底完整性出错: " + e.getMessage());
        }
        
        return new SystemHealthCheckResult(issues.isEmpty() && errors.isEmpty(), issues, errors);
    }

    /**
     * 检查用户是否缺失生词本或已掌握词书
     */
    public SystemHealthCheckResult checkMissingUserDicts() {
        List<SystemHealthIssue> issues = new ArrayList<>();
        List<String> errors = new ArrayList<>();
        
        try {
            // 使用一条 SQL 查询同时找出缺少"生词本"或"已掌握"词书的用户
            String sql = "SELECT u.id, u.user_name, u.nick_name, '生词本' as missing_dict " +
                        "FROM \"user\" u " +
                        "LEFT JOIN dict d ON u.id = d.owner_id AND d.name = '生词本' " +
                        "WHERE d.id IS NULL " +
                        "UNION ALL " +
                        "SELECT u.id, u.user_name, u.nick_name, '已掌握' as missing_dict " +
                        "FROM \"user\" u " +
                        "LEFT JOIN dict d ON u.id = d.owner_id AND d.name = '已掌握' " +
                        "WHERE d.id IS NULL " +
                        "ORDER BY missing_dict, id";
            
            List<Object[]> missingDicts = namedParameterJdbcTemplate.query(sql, 
                new MapSqlParameterSource(), 
                (rs, rowNum) -> new Object[]{
                    rs.getString("id"),
                    rs.getString("user_name"),
                    rs.getString("nick_name"),
                    rs.getString("missing_dict")
                }
            );
            
            // 将查询结果转换为问题列表
            for (Object[] record : missingDicts) {
                String userId = (String) record[0];
                String userName = (String) record[1];
                String nickName = (String) record[2];
                String missingDict = (String) record[3];
                
                issues.add(new SystemHealthIssue(
                    "用户缺失词书",
                    String.format("用户 %s (%s, ID: %s) 缺少词书：%s", 
                                nickName != null ? nickName : userName, userName, userId, missingDict),
                    "missing_user_dict"
                ));
            }
            
        } catch (DataAccessException e) {
            errors.add("检查用户词书缺失时出错: " + e.getMessage());
        }
        
        return new SystemHealthCheckResult(issues.isEmpty() && errors.isEmpty(), issues, errors);
    }

    /**
     * 检查单词配图完整性 (检查配图文件是否存在及数据是否有效)
     */
    public SystemHealthCheckResult checkWordImageIntegrity() {
        List<SystemHealthIssue> issues = new ArrayList<>();
        List<String> errors = new ArrayList<>();
        
        try {
            // 获取所有配图记录
            String sql = "SELECT id, image_file FROM word_image";
            List<Object[]> images = namedParameterJdbcTemplate.query(sql, new MapSqlParameterSource(), (rs, rowNum) -> 
                new Object[]{
                    rs.getString("id"),
                    rs.getString("image_file")
                }
            );
            
            String baseDir = sysParamUtil.getImageBaseDir() + "/word/";
            int missingOrInvalidCount = 0;
            
            for (Object[] image : images) {
                String fileName = (String) image[1];
                if (fileName == null || fileName.trim().isEmpty()) {
                    missingOrInvalidCount++;
                    continue;
                }
                File file = new File(baseDir + fileName);
                if (!MyImage.isValidImage(file)) {
                    missingOrInvalidCount++;
                }
            }
            
            if (missingOrInvalidCount > 0) {
                issues.add(new SystemHealthIssue(
                    "配图文件缺失或损坏",
                    String.format("发现 %d 条配图记录对应的物理文件不存在或为损坏/非有效图片（如 HTML 错误页）", missingOrInvalidCount),
                    "word_image_integrity"
                ));
            }
            
        } catch (Exception e) {
            errors.add("检查单词配图完整性时出错: " + e.getMessage());
        }
        
        return new SystemHealthCheckResult(issues.isEmpty() && errors.isEmpty(), issues, errors);
    }

    /**
     * 检查例句发音完整性 (检查音频文件是否存在)
     */
    public SystemHealthCheckResult checkSentenceAudioIntegrity() {
        List<SystemHealthIssue> issues = new ArrayList<>();
        List<String> errors = new ArrayList<>();
        
        try {
            // 获取所有摘要不为空的例句记录
            String sql = "SELECT id, english_digest FROM sentence WHERE english_digest IS NOT NULL AND english_digest != ''";
            List<Object[]> sentences = namedParameterJdbcTemplate.query(sql, new MapSqlParameterSource(), (rs, rowNum) -> 
                new Object[]{
                    rs.getString("id"),
                    rs.getString("english_digest")
                }
            );
            
            String baseDir = sysParamUtil.getSoundPath() + "/sentence/";
            int missingCount = 0;
            
            for (Object[] sentence : sentences) {
                String digest = (String) sentence[1];
                java.io.File file = new java.io.File(baseDir + digest + ".mp3");
                if (!file.exists()) {
                    missingCount++;
                }
            }
            
            logger.info("例句发音完整性检查完成：扫描 {} 条记录，发现 {} 条缺失音频文件", sentences.size(), missingCount);
            
            if (missingCount > 0) {
                issues.add(new SystemHealthIssue(
                    "例句发音文件缺失",
                    String.format("发现 %d 条例句记录对应的物理发音文件不存在", missingCount),
                    "sentence_audio_integrity"
                ));
            }
            
        } catch (Exception e) {
            errors.add("检查例句发音完整性时出错: " + e.getMessage());
        }
        
        return new SystemHealthCheckResult(issues.isEmpty() && errors.isEmpty(), issues, errors);
    }

    /**
     * 自动修复系统问题
     */
    public SystemHealthFixResult autoFixSystemIssues(List<String> issueTypes) {
        List<String> fixed = new ArrayList<>();
        List<String> errors = new ArrayList<>();
        int fixedCount = 0;
        
        try {
            for (String issueType : issueTypes) {
                switch (issueType) {
                    case "system_dict_integrity" -> fixedCount += fixSystemDictIntegrity(fixed);
                    case "user_dict_integrity" -> fixedCount += fixUserDictIntegrity(fixed);
    
                    case "db_version" -> fixedCount += fixDbVersionConsistency(fixed);
                    case "common_dict_integrity" -> fixedCount += fixCommonDictIntegrity(fixed);
                    case "sys_dict_missing_fallback" -> fixedCount += fixSystemDictMissingFallback(fixed);
                    case "missing_raw_word_dict", "missing_user_dict" -> fixedCount += fixMissingUserDicts(fixed);
                    case "word_image_integrity" -> fixedCount += fixWordImageIntegrity(fixed);
                    case "sentence_audio_integrity" -> fixedCount += fixSentenceAudioIntegrity(fixed);
                    // 没有对应修复动作的问题类型（例如只读体检项 learning_progress_inconsistent）：
                    // 无事可做，静默跳过。报"未知类型"会把只读体检的发现误报成修复失败。
                    default -> {
                    }
                }
                // fixedCount += fixLearningProgress(fixed);
                            }
        } catch (Exception e) {
            errors.add("自动修复过程中出错: " + e.getMessage());
        }
        
        return new SystemHealthFixResult(fixedCount, errors, fixed);
    }

    // 私有辅助方法

    /**
     * 修复单词缺失 0 库物理托底的问题
     */
    private int fixSystemDictMissingFallback(List<String> fixed) {
        int fixedCount = 0;
        try {
            String sqlWords1 = "SELECT DISTINCT word_id FROM dict_word WHERE word_id NOT IN (SELECT word_id FROM dict_word WHERE dict_id = '0')";
            List<String> missingPhysical = namedParameterJdbcTemplate.query(sqlWords1, new MapSqlParameterSource(), (rs, rowNum) -> rs.getString("word_id"));
            
            if (!missingPhysical.isEmpty()) {
                Dict commonDict = dictBo.findById(Constants.COMMON_DICT_ID);
                int maxSeq = dictWordBo.getMaxSeqNo(commonDict);
                
                for (String wordId : missingPhysical) {
                    try {
                        maxSeq++;
                        DictWord dw0 = new DictWord();
                        dw0.setId(new DictWordId(Constants.COMMON_DICT_ID, wordId));
                        dw0.setDict(commonDict);
                        Word word = new Word();
                        word.setId(wordId);
                        dw0.setWord(word);
                        dw0.setSeq(maxSeq);
                        dw0.setCreateTime(new java.util.Date());
                        dictWordBo.createEntity(dw0);
                        
                        DictWordDto dwDto = new DictWordDto();
                        dwDto.setDictId(Constants.COMMON_DICT_ID);
                        dwDto.setWordId(wordId);
                        dwDto.setSeq(dw0.getSeq());
                        dwDto.setUnit(dw0.getUnit());
                        dwDto.setCreateTime(dw0.getCreateTime());
                        sysDbSyncBo.logOperation(dwDto, "INSERT", "dict_word", Constants.COMMON_DICT_ID + "_" + wordId, JsonUtils.toJson(dwDto));
                        fixedCount++;
                    } catch (Exception ignore) {}
                }
                if (fixedCount > 0) {
                    commonDict.setWordCount(maxSeq);
                    dictBo.updateEntity(commonDict);
                    sysDbSyncBo.logOperation(commonDict, "UPDATE", "dict", Constants.COMMON_DICT_ID, JsonUtils.toJson(dictBo.toDto(commonDict)));
                }
                fixed.add(String.format("成功为 %d 个物理脱离单词补充并广播到 0 库。", fixedCount));
            }
        } catch (Exception e) {
            fixed.add("修复底层物理托底数据失败: " + e.getMessage());
        }
        return fixedCount;
    }

    /**
     * 为客户端提供点对点的托底防空洞救转数据，直接打包返回指定单词的全套资源。
     * 优先搜索系统公库（0库），如果没找到，则搜索该用户的私有词库。
     */
    public java.util.Map<String, Object> getFallbackWordsData(List<String> wordIds, String userId) {
        List<DictWordDto> dictWords = new ArrayList<>();
        List<MeaningItemDto> meaningItems = new ArrayList<>();
        List<SentenceDto> sentences = new ArrayList<>();
        List<String> unrecognizedWordIds = new ArrayList<>();
        
        if (wordIds != null) {
            for (String wordId : wordIds) {
                String foundDictId = null;

                Word word = wordBo.findById(wordId);
                if (word == null) {
                    // 云端主库根本没有该词，说明属于历史因事务割裂残留的幽灵脏数据
                    unrecognizedWordIds.add(wordId);
                    logger.warn("【健康检查】发现客户端请求的单词在云端完全不存在(幽灵词): wordId={}", wordId);
                    try {
                        sysDbSyncBo.logOperation("DELETE", "dict_word", Constants.COMMON_DICT_ID + "_" + wordId, "{}");
                        sysDbSyncBo.logOperation("DELETE", "word", wordId, "{}");
                    } catch (Exception ignore) {}
                    continue;
                }
                
                // 1. 优先尝试从系统公共库（0库）找
                DictWord dw = dictWordBo.findById(new DictWordId(Constants.COMMON_DICT_ID, wordId));
                if (dw != null) {
                    foundDictId = Constants.COMMON_DICT_ID;
                    logger.info(String.format("【健康检查】在通用词典(0)找到单词: wordId=%s", wordId));
                    DictWordDto dwDto = new DictWordDto();
                    dwDto.setDictId(Constants.COMMON_DICT_ID);
                    dwDto.setWordId(wordId);
                    dwDto.setSeq(dw.getSeq());
                    dwDto.setUnit(dw.getUnit());
                    dwDto.setCreateTime(dw.getCreateTime());
                    dwDto.setUpdateTime(dw.getUpdateTime());
                    dictWords.add(dwDto);
                } else if (userId != null && !userId.isEmpty()) {
                    // 2. 如果公共库没找到，尝试从该用户的私有库里找
                    List<Dict> userDicts = dictBo.getDictsByOwnerId(userId, null);
                    for (Dict dict : userDicts) {
                        DictWord udw = dictWordBo.findById(new DictWordId(dict.getId(), wordId));
                        if (udw != null) {
                            foundDictId = dict.getId();
                            logger.info(String.format("【健康检查】在用户私有词典[%s]找到单词: wordId=%s", dict.getName(), wordId));
                            DictWordDto dwDto = new DictWordDto();
                            dwDto.setDictId(dict.getId());
                            dwDto.setWordId(wordId);
                            dwDto.setSeq(udw.getSeq());
                            dwDto.setUnit(udw.getUnit());
                            dwDto.setCreateTime(udw.getCreateTime());
                            dwDto.setUpdateTime(udw.getUpdateTime());
                            dictWords.add(dwDto);
                            break; // 只要找到一个私有库包含该词即可
                        }
                    }
                }
                
                // 3. 如果找到了物理位置（无论是公库还是私库），则提取其在该词库下的关联资源
                if (foundDictId != null) {
                    List<MeaningItemDto> mDtos = meaningItemBo.findMeaningsByWordAndDict(wordId, foundDictId);
                    if (mDtos != null && !mDtos.isEmpty()) {
                        logger.info(String.format("【健康检查】找到释义项: wordId=%s, dictId=%s, 数量=%d", wordId, foundDictId, mDtos.size()));
                        meaningItems.addAll(mDtos);
                        for (MeaningItemDto mDto : mDtos) {
                            List<Sentence> sList = sentenceBo.findByMeaningItem(mDto.getId());
                            if (sList != null && !sList.isEmpty()) {
                                logger.info(String.format("【健康检查】找到关联例句: meaningId=%s, 数量=%d", mDto.getId(), sList.size()));
                                for (Sentence s : sList) {
                                    sentences.add(sentenceBo.toDto(s));
                                }
                            }
                        }
                    } else {
                        logger.info(String.format("【健康检查】警告：虽然找到了词库关联，但未找到对应的释义项: wordId=%s, dictId=%s", wordId, foundDictId));
                    }
                } else {
                    logger.info(String.format("【健康检查】在通用词典和用户私有词典中均未找到该单词: wordId=%s", wordId));
                }
            }
        }
        
        java.util.Map<String, Object> data = new java.util.HashMap<>();
        data.put("dictWords", dictWords);
        data.put("meaningItems", meaningItems);
        data.put("sentences", sentences);
        data.put("unrecognizedWordIds", unrecognizedWordIds);
        return data;
    }

    /**
     * 修复单词配图完整性 (删除缺失或损坏的配图记录及脏文件，并记录同步日志)
     */
    private int fixWordImageIntegrity(List<String> fixed) {
        int fixedCount = 0;
        try {
            // 这里为了安全，先查出所有记录，再逐个确认文件缺失或损坏
            String sql = "SELECT id, image_file FROM word_image";
            List<Object[]> images = namedParameterJdbcTemplate.query(sql, new MapSqlParameterSource(), (rs, rowNum) -> 
                new Object[]{
                    rs.getString("id"),
                    rs.getString("image_file")
                }
            );
            
            String baseDir = sysParamUtil.getImageBaseDir() + "/word/";
            
            for (Object[] image : images) {
                String id = (String) image[0];
                String fileName = (String) image[1];
                
                boolean invalid = false;
                if (fileName == null || fileName.trim().isEmpty()) {
                    invalid = true;
                } else {
                    File file = new File(baseDir + fileName);
                    if (!MyImage.isValidImage(file)) {
                        invalid = true;
                    }
                }

                if (invalid) {
                    try {
                        // 使用 wordImageBo 的删除逻辑，它会记录 sys_db_log 并清理事件记录及删除物理文件
                        // 管理员身份删除 (sys_user_id)
                        String sysUserId = userBo.getSysUser_sys(false).getId();
                        User sysUser = userBo.findById(sysUserId);
                        wordImageBo.deleteWordImage(id, sysUser, false);
                        fixedCount++;
                    } catch (Exception e) {
                        fixed.add("修复记录 [" + id + "] 失败: " + e.getMessage());
                    }
                }
            }
            
            if (fixedCount > 0) {
                fixed.add(String.format("成功清理了 %d 条缺失或损坏的配图记录，并已生成同步日志。", fixedCount));
            }
        } catch (Exception e) {
            fixed.add("修复单词配图完整性时出错: " + e.getMessage());
        }
        return fixedCount;
    }

    /**
     * 修复例句发音完整性 (将缺失文件的例句标记为等待 TTS)
     */
    private int fixSentenceAudioIntegrity(List<String> fixed) {
        int fixedCount = 0;
        try {
            String sql = "SELECT id, english_digest FROM sentence WHERE english_digest IS NOT NULL AND english_digest != ''";
            List<Object[]> sentences = namedParameterJdbcTemplate.query(sql, new MapSqlParameterSource(), (rs, rowNum) -> 
                new Object[]{
                    rs.getString("id"),
                    rs.getString("english_digest")
                }
            );
            
            String baseDir = sysParamUtil.getSoundPath() + "/sentence/";
            List<String> missingIds = new ArrayList<>();
            
            for (Object[] sentence : sentences) {
                String id = (String) sentence[0];
                String digest = (String) sentence[1];
                java.io.File file = new java.io.File(baseDir + digest + ".mp3");
                if (!file.exists()) {
                    missingIds.add(id);
                }
            }
            
            if (!missingIds.isEmpty()) {
                logger.info("开始修复例句发音完整性：准备更新 {} 条记录", missingIds.size());
                // 分批更新，避免 SQL 过长
                int batchSize = 500;
                for (int i = 0; i < missingIds.size(); i += batchSize) {
                    List<String> batch = missingIds.subList(i, Math.min(i + batchSize, missingIds.size()));
                    String updateSql = "UPDATE sentence SET need_tts = true, the_type = :type WHERE id IN (:ids)";
                    MapSqlParameterSource params = new MapSqlParameterSource();
                    params.addValue("type", Sentence.WAITTING_TTS);
                    params.addValue("ids", batch);
                    fixedCount += namedParameterJdbcTemplate.update(updateSql, params);
                }
                fixed.add(String.format("成功将 %d 条缺失发音的例句标记为等待 TTS 重新生成。", fixedCount));
                logger.info("例句发音完整性修复完成：已成功更新 {} 条记录的状态", fixedCount);
            } else {
                logger.info("例句发音完整性修复：未发现需要修复的记录");
            }
        } catch (Exception e) {
            fixed.add("修复例句发音完整性时出错: " + e.getMessage());
        }
        return fixedCount;
    }

    /**
     * 检查词典单词序号连续性和数量一致性（参考check_db.py的高效实现）
     */
    private void checkDictWordSequenceAndCount(String dictId, String dictName, String ownerId, Integer expectedWordCount, String baseDictId, List<SystemHealthIssue> issues) {
        if (baseDictId != null && !baseDictId.trim().isEmpty()) {
            return; // 衍生版（乱序版）词书本质上是一个共享源词库实体的空壳，不应该检查 dict_word
        }
        try {
            // 使用原生SQL一次性获取词典中的所有单词，按seq排序
            String sql = "SELECT dw.word_id, dw.seq, w.spell " +
                        "FROM dict_word dw " +
                        "JOIN word w ON dw.word_id = w.id " +
                        "WHERE dw.dict_id = :dictId " +
                        "ORDER BY dw.seq ASC";
            
            MapSqlParameterSource params = new MapSqlParameterSource("dictId", dictId);
            List<Object[]> dictWords = namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> 
                new Object[]{
                    rs.getString("word_id"),
                    rs.getObject("seq", Integer.class),
                    rs.getString("spell")
                }
            );
            
            // 检查空词书
            if (dictWords.isEmpty()) {
                // 系统用户的生词本和已掌握词书（核心词书）允许为空
                boolean isSystemUserCoreDict = Constants.SYS_USER_SYS_ID.equals(ownerId) && 
                        ("生词本".equals(dictName) || "已掌握".equals(dictName));
                
                if (Constants.SYS_USER_SYS_ID.equals(ownerId) && !isSystemUserCoreDict) {
                    // 其他系统词书如果为空，是异常情况
                    issues.add(new SystemHealthIssue(
                        "系统词书为空",
                        String.format("系统词书 %s 为空，需要删除", dictName),
                        "empty_system_dict"
                    ));
                } else if (!isSystemUserCoreDict) {
                    // 如果词书为空但dict表记录的wordCount不为0，这也是个问题
                    if (expectedWordCount != null && expectedWordCount != 0) {
                        issues.add(new SystemHealthIssue(
                            "单词数量不匹配",
                            String.format("词典 %s 为空，但dict表记录wordCount=%d", dictName, expectedWordCount),
                            "word_count_mismatch"
                        ));
                    }
                }
                // 系统用户的核心词书允许为空，直接返回，不报告问题
                return;
            }
            
            int actualWordCount = dictWords.size();
            
            // 检查单词数量是否和dict表一致
            if (expectedWordCount != null && actualWordCount != expectedWordCount) {
                issues.add(new SystemHealthIssue(
                    "单词数量不匹配",
                    String.format("词典 %s 元数据(Metadata)记录数: %d, 数据库实际关联单词数: %d", dictName, expectedWordCount, actualWordCount),
                    "dict_word_count"
                ));
            }
            
            // 稀疏保序架构：用户词典自然允许删除产生的稀疏空洞，仅检查是否存在非法非正数序号
            for (Object[] dw : dictWords) {
                Integer seq = (Integer) dw[1];
                if (seq == null || seq <= 0) {
                    String wordSpell = (String) dw[2];
                    issues.add(new SystemHealthIssue(
                        "序号非法",
                        String.format("词典 %s 单词 '%s' 序号非法: %s (必须大于0)", dictName, wordSpell, seq),
                        "dict_word_sequence"
                    ));
                    break;
                }
            }
            
        } catch (DataAccessException e) {
            issues.add(new SystemHealthIssue(
                "检查序号连续性失败",
                String.format("检查词典 %s 序号连续性时出错: %s", dictName, e.getMessage()),
                "dict_word_sequence"
            ));
        }
    }

    private void checkDictWordSequence(String dictId, List<SystemHealthIssue> issues) {
        try {
            List<Object[]> dictWords = dictBo.checkDictWordSequence(dictId);
            
            // 获取词典信息
            Dict dict = dictBo.findById(dictId, false);
            if (dict == null) {
                issues.add(new SystemHealthIssue(
                    "词典不存在",
                    String.format("词典 %s 不存在", dictId),
                    "dict_word_sequence"
                ));
                return;
            }
            
            if (dict.getBaseDictId() != null && !dict.getBaseDictId().trim().isEmpty()) {
                return; // 衍生版直接跳过实体检查
            }
            
            // 检查空词书
            if (dictWords.isEmpty()) {
                // 系统用户的生词本和已掌握词书（核心系统词书）允许为空
                boolean isSystemUserCoreDict = Constants.SYS_USER_SYS_ID.equals(dict.getOwner().getId()) 
                        && ("生词本".equals(dict.getName()) || "已掌握".equals(dict.getName()));
                
                if (Constants.SYS_USER_SYS_ID.equals(dict.getOwner().getId()) && !isSystemUserCoreDict) {
                    // 其他系统词书如果为空，是异常情况
                    issues.add(new SystemHealthIssue(
                        "系统词书为空",
                        String.format("系统词书 %s 为空，需要删除", dict.getName()),
                        "empty_system_dict"
                    ));
                } else if (!isSystemUserCoreDict) {
                    // 如果词书为空但dict表记录的wordCount不为0，这也是个问题
                    if (dict.getWordCount() != 0) {
                        issues.add(new SystemHealthIssue(
                            "单词数量不匹配",
                            String.format("词书 %s 为空，但dict表记录wordCount=%d", dict.getName(), dict.getWordCount()),
                            "word_count_mismatch"
                        ));
                    }
                }
                // 系统用户的核心系统词书允许为空，直接返回，不报告问题
                return;
            }
            
            // 检查序号是否从1开始
            Integer firstSeq = (Integer) dictWords.get(0)[1];
            if (firstSeq != 1) {
                issues.add(new SystemHealthIssue(
                    "序号不连续",
                    String.format("词典 %s 第一个单词序号不是1，实际是%d", dict.getName(), firstSeq),
                    "dict_word_sequence"
                ));
                return;
            }
            
            // 检查序号是否连续
            for (int i = 0; i < dictWords.size(); i++) {
                Integer expectedSeq = i + 1;
                Integer actualSeq = (Integer) dictWords.get(i)[1];
                if (!expectedSeq.equals(actualSeq)) {
                    String wordId = (String) dictWords.get(i)[0];
                    String spell = (String) dictWords.get(i)[2];
                    issues.add(new SystemHealthIssue(
                        "序号不连续",
                        String.format("词典 %s 中单词 %s(%s) 序号不正确，期望%d，实际%d", 
                                    dict.getName(), wordId, spell, expectedSeq, actualSeq),
                        "dict_word_sequence"
                    ));
                    return;
                }
            }
            
            // 检查最大序号是否等于总单词数
            Integer lastSeq = (Integer) dictWords.get(dictWords.size() - 1)[1];
            if (!lastSeq.equals(dictWords.size())) {
                issues.add(new SystemHealthIssue(
                    "序号不连续",
                    String.format("词典 %s 最大序号(%d)不等于总单词数(%d)", 
                                dict.getName(), lastSeq, dictWords.size()),
                    "dict_word_sequence"
                ));
            }
        } catch (Exception e) {
            issues.add(new SystemHealthIssue(
                "检查序号连续性失败",
                String.format("检查词典 %s 序号连续性时出错: %s", dictId, e.getMessage()),
                "dict_word_sequence"
            ));
        }
    }

    private void checkDictWordCount(String dictId, List<SystemHealthIssue> issues) {
        try {
            Long actualCount = dictBo.getDictWordCount(dictId);
            Integer recordedCount = dictBo.getDictRecordedWordCount(dictId);
            
            // 获取词典信息
            Dict dict = dictBo.findById(dictId, false);
            if (dict == null) {
                issues.add(new SystemHealthIssue(
                    "词典不存在",
                    String.format("词典 %s 不存在", dictId),
                    "dict_word_count"
                ));
                return;
            }
            
            if (dict.getBaseDictId() != null && !dict.getBaseDictId().trim().isEmpty()) {
                return; // 衍生版直接跳过实体数量检查
            }
            
            if (!actualCount.equals(recordedCount.longValue())) {
                issues.add(new SystemHealthIssue(
                    "单词数量不匹配",
                    String.format("词典 %s 元数据(Metadata)记录数: %d, 数据库实际关联单词数: %d", 
                                dict.getName(), recordedCount, actualCount),
                    "dict_word_count"
                ));
            }
        } catch (Exception e) {
            issues.add(new SystemHealthIssue(
                "检查单词数量失败",
                String.format("检查词典 %s 单词数量时出错: %s", dictId, e.getMessage()),
                "dict_word_count"
            ));
        }
    }

    private int fixSystemDictIntegrity(List<String> fixed) {
        int fixedCount = 0;
        try {
            List<String> systemDictIds = dictBo.getSystemDictIds();
            for (String dictId : systemDictIds) {
                Dict dict = dictBo.findById(dictId, false);
                if (dict == null) continue;
                
                // 检查是否为空词书
                Long actualCount = dictBo.getDictWordCount(dictId);
                if (actualCount == 0) {
                    // 系统核心词书（生词本、已掌握）即使为空也不应删除
                    boolean isSystemUserCoreDict = "生词本".equals(dict.getName()) || "已掌握".equals(dict.getName());
                    if (!isSystemUserCoreDict) {
                        // 使用安全删除方法删除空的系统词书
                        dictBo.deleteDictSafely(dictId);
                        fixed.add("删除空的系统词书: " + dict.getName());
                        fixedCount++;
                    }
                } else {
                    // 修复序号
                    dictBo.fixDictWordSequence(dictId);
                    
                    // 修复数量
                    dictBo.updateDictWordCount(dictId, actualCount.intValue());
                    
                    fixed.add("修复系统词典 " + dict.getName() + " 的完整性问题");
                    fixedCount++;
                }
            }
        } catch (Exception e) {
            org.slf4j.LoggerFactory.getLogger(SystemHealthCheckBo.class).error("自动修复失败", e);
        }
        return fixedCount;
    }

    private int fixUserDictIntegrity(List<String> fixed) {
        int fixedCount = 0;
        try {
            List<String> userDictIds = dictBo.getUserDictIds();
            for (String dictId : userDictIds) {
                // 稀疏保序架构：用户词典自然允许稀疏空洞，严禁在服务端静默重排改写 seq（避免端云不一致）。
                // 仅当元数据 word_count 与实际关联数不一致时才做同步修复
                Long actualCount = dictBo.getDictWordCount(dictId);
                Integer recordedCount = dictBo.getDictRecordedWordCount(dictId);
                if (actualCount != null && (recordedCount == null || actualCount.intValue() != recordedCount)) {
                    dictBo.updateDictWordCount(dictId, actualCount.intValue());
                    fixed.add(String.format("修复用户词典 %s 单词数量元数据: %s -> %d", dictId, recordedCount, actualCount));
                    fixedCount++;
                }
            }
        } catch (Exception e) {
            org.slf4j.LoggerFactory.getLogger(SystemHealthCheckBo.class).error("自动修复用户词典失败", e);
        }
        return fixedCount;
    }


    private int fixDbVersionConsistency(List<String> fixed) {
        int fixedCount = 0;
        try {
            List<Object[]> userVersions = userDbVersionDao.getAllUserVersions();
            for (Object[] userVersion : userVersions) {
                String userId = (String) userVersion[0];
                Integer currentVersion = (Integer) userVersion[1];
                
                int invalidLogCount = userDbVersionDao.countInvalidLogs(userId, currentVersion);
                if (invalidLogCount > 0) {
                    userDbVersionDao.deleteInvalidLogs(userId, currentVersion);
                    fixed.add(String.format("删除用户 %s 的 %d 条异常日志", userId, invalidLogCount));
                    fixedCount++;
                }
            }
        } catch (Exception e) {
            org.slf4j.LoggerFactory.getLogger(SystemHealthCheckBo.class).error("自动修复失败", e);
        }
        return fixedCount;
    }

    private int fixCommonDictIntegrity(List<String> fixed) {
        String commonDictId = "0";
        int totalFixed = 0;

        // 0. 确保所有 Word 表中的单词都在通用词典中
        try {
            String sqlMissing = "SELECT id FROM word WHERE id NOT IN (SELECT word_id FROM dict_word WHERE dict_id = '0')";
            List<String> missingFromCommon = namedParameterJdbcTemplate.query(sqlMissing, new MapSqlParameterSource(), (rs, rowNum) -> rs.getString("id"));
            if (!missingFromCommon.isEmpty()) {
                Dict commonDict = dictBo.findById(commonDictId);
                int maxSeq = dictWordBo.getMaxSeqNo(commonDict);
                for (String wordId : missingFromCommon) {
                    maxSeq++;
                    DictWord dw0 = new DictWord();
                    dw0.setId(new DictWordId(commonDictId, wordId));
                    dw0.setDict(commonDict);
                    Word word = new Word();
                    word.setId(wordId);
                    dw0.setWord(word);
                    dw0.setSeq(maxSeq);
                    dw0.setCreateTime(new java.util.Date());
                    dictWordBo.createEntity(dw0);
                    
                    DictWordDto dwDto = new DictWordDto();
                    dwDto.setDictId(commonDictId);
                    dwDto.setWordId(wordId);
                    dwDto.setSeq(dw0.getSeq());
                    dwDto.setUnit(dw0.getUnit());
                    dwDto.setCreateTime(dw0.getCreateTime());
                    sysDbSyncBo.logOperation(dwDto, "INSERT", "dict_word", commonDictId + "_" + wordId, JsonUtils.toJson(dwDto));
                }
                fixed.add(String.format("成功向通用词典补齐了 %d 个缺失的单词记录。", missingFromCommon.size()));
                totalFixed += missingFromCommon.size();
            }
        } catch (Exception e) {
            logger.error("向通用词典补齐单词记录时出错", e);
        }

        // 1. 修复缺失的释义：从其他词库拷贝一份作为 0 库托底
        List<String> wordsWithoutMeanings = meaningItemBo.findWordsWithoutMeanings(commonDictId);
        if (wordsWithoutMeanings != null && !wordsWithoutMeanings.isEmpty()) {
            List<MeaningItemDto> candidates = meaningItemBo.getOneMeaningPerWordFromAnyDict(wordsWithoutMeanings);
            Set<String> fixedByCopy = new HashSet<>();
            int fixedMeaningCount = 0;
            if (candidates != null) {
                for (MeaningItemDto mDto : candidates) {
                    boolean copied = false;
                    // 拷贝来源若用分号挤进了多个义项，同样按约定拆成多条独立释义项
                    for (String part : Util.splitMeanings(mDto.getMeaning())) {
                        try {
                            mDto.setId(Util.uuid());
                            mDto.setMeaning(part);
                            mDto.setDictId(commonDictId);
                            mDto.setOwnerId(Constants.SYS_USER_SYS_ID);
                            mDto.setCreateTime(new java.util.Date());
                            mDto.setUpdateTime(new java.util.Date());

                            meaningItemBo.createMeaningItem(mDto);
                            sysDbSyncBo.logOperation("INSERT", "meaning_item", mDto.getId(), JsonUtils.toJson(mDto));
                            fixedMeaningCount++;
                            copied = true;
                        } catch (Exception ignore) {}
                    }
                    if (copied) {
                        fixedByCopy.add(mDto.getWordId());
                    }
                }
            }
            if (fixedMeaningCount > 0) {
                fixed.add(String.format("成功为 %d 个单词补全了通用词典 0 库释义（从其他词典拷贝）。", fixedMeaningCount));
                totalFixed += fixedMeaningCount;
            }

            // 2. 针对无法从外部拷贝释义的单词，排查是脏数据还是纯孤立单词
            int aiFixedCount = 0;
            int cleanedCount = 0;
            for (String wordId : wordsWithoutMeanings) {
                if (fixedByCopy.contains(wordId)) continue;
                
                Word word = wordBo.findById(wordId);
                // 场景 A: 这是一个孤儿“脏数据”（Word 表中根本不存在此单词）
                if (word == null || word.getSpell() == null || word.getSpell().trim().isEmpty()) {
                    try {
                        String deleteSql = "DELETE FROM dict_word WHERE dict_id = :dictId AND word_id = :wordId";
                        MapSqlParameterSource delParams = new MapSqlParameterSource();
                        delParams.addValue("dictId", commonDictId);
                        delParams.addValue("wordId", wordId);
                        namedParameterJdbcTemplate.update(deleteSql, delParams);
                        
                        // 记录同步日志，通知客户端删除此记录
                        DictWordDto dwDto = new DictWordDto();
                        dwDto.setDictId(commonDictId);
                        dwDto.setWordId(wordId);
                        sysDbSyncBo.logOperation(dwDto, "DELETE", "dict_word", commonDictId + "_" + wordId, JsonUtils.toJson(dwDto));
                        
                        logger.info(String.format("【健康检查】清理脏数据: wordId=%s", wordId));
                        cleanedCount++;
                    } catch (Exception ignore) {}
                    continue;
                }
                
                // 场景 B: 存在拼写，但所有地方都缺少释义 -> 动用 AI
                try {
                    String spell = word.getSpell();
                    String systemPrompt = "你是一个专业的词典编撰者。请为指定的英文单词生成一段中文释义和该释义对应的词性。严格只返回 JSON 对象，格式为：{\"ciXing\": \"n./v./adj.等\", \"meaning\": \"中文释义\"}。不要包含任何 markdown 格式标记或其他多余文字！";
                    String promptText = "单词：[" + spell + "]";
                    String rawOutput = aiBo.generateText(systemPrompt, promptText);
                    
                    if (rawOutput != null) {
                        java.util.Map<String, Object> map = JsonUtils.parseAiMap(rawOutput);
                        if (map != null && map.containsKey("meaning")) {
                            String ciXing = map.containsKey("ciXing") ? (String) map.get("ciXing") : "";
                            String meaning = (String) map.get("meaning");
                            logger.info(String.format("【健康检查】AI 为单词 [%s] 生成了释义: %s", spell, meaning));

                            // AI 偶发违约：一条释义里用分号挤进了多个义项，按约定拆成多条独立释义项
                            for (String part : Util.splitMeanings(meaning)) {
                                MeaningItemDto newMeaning = new MeaningItemDto();
                                newMeaning.setId(Util.uuid());
                                newMeaning.setWordId(wordId);
                                newMeaning.setDictId(commonDictId);
                                newMeaning.setCiXing(ciXing);
                                newMeaning.setMeaning(part);
                                newMeaning.setOwnerId(Constants.SYS_USER_SYS_ID);
                                newMeaning.setPopularity(1);
                                newMeaning.setCreateTime(new java.util.Date());
                                newMeaning.setUpdateTime(new java.util.Date());

                                meaningItemBo.createMeaningItem(newMeaning);
                                sysDbSyncBo.logOperation("INSERT", "meaning_item", newMeaning.getId(), JsonUtils.toJson(newMeaning));
                                aiFixedCount++;
                            }
                        }
                    }
                } catch (Exception e) {
                    org.slf4j.LoggerFactory.getLogger(SystemHealthCheckBo.class).warn("通过 AI 补齐通用释义失败 wordId=" + wordId, e);
                }
            }
            
            if (cleanedCount > 0) {
                fixed.add(String.format("成功从 0 库索引中清理了 %d 个不存在对应实体的脏数据。", cleanedCount));
                totalFixed += cleanedCount;
            }
            if (aiFixedCount > 0) {
                fixed.add(String.format("成功通过 AI 为 %d 个孤立单词生成并补全了释义项。", aiFixedCount));
                totalFixed += aiFixedCount;
            }
        }

        // 2. 修复缺失的例句：AI 补齐逻辑
        List<String> meaningsWithoutSentences = sentenceBo.findMeaningsWithoutSentences(commonDictId);
        if (meaningsWithoutSentences == null || meaningsWithoutSentences.isEmpty()) {
            return totalFixed;
        }

        new Thread(() -> {
            try {
                org.slf4j.Logger logger = org.slf4j.LoggerFactory.getLogger(SystemHealthCheckBo.class);
                logger.info("开始后台修复通用词典的 {} 个缺失例句的释义项...", meaningsWithoutSentences.size());
                
                String systemPrompt = "你是一个专业的外教，任务是专门给英语单词造例句。给定单词、词性和释义，请生成一条原生地道的英语例句及对应的中文翻译。严格只返回 JSON 对象，格式为：{\"sentenceEn\": \"英文例句\", \"sentenceCn\": \"中文翻译\"}。不要包含 markdown 或其他字符！";

                for (String meaningId : meaningsWithoutSentences) {
                    try {
                        MeaningItem mi = meaningItemBo.findById(meaningId);
                        if (mi == null) continue;
                        
                        Word stubWord = mi.getWord();
                        if (stubWord == null || stubWord.getId() == null) continue;
                        
                        Word word = wordBo.findById(stubWord.getId());
                        if (word == null || word.getSpell() == null) continue;
                        
                        String spell = word.getSpell();
                        String promptText = "单词：[" + spell + "]\n要求：请造一个能准确反映词性[" + (mi.getCiXing() != null ? mi.getCiXing() : "未知") + "] 和释义[" + mi.getMeaning() + "]的例句。只返回JSON。";
                        
                        String rawOutput = aiBo.generateText(systemPrompt, promptText);
                        
                        if (rawOutput != null) {
                            java.util.Map<String, Object> map = JsonUtils.parseAiMap(rawOutput);
                            if (map != null && map.containsKey("sentenceEn")) {
                                String sentenceEn = (String) map.get("sentenceEn");
                                String sentenceCn = (String) map.get("sentenceCn");
                                    
                                Sentence sentence = new Sentence();
                                sentence.setId(Util.uuid());
                                sentence.setEnglish(sentenceEn);
                                sentence.setChinese(sentenceCn);
                                sentence.setWordMeaning(mi.getMeaning());
                                sentence.setPartOfSpeech(mi.getCiXing());
                                sentence.setMeaningItem(mi);
                                sentence.setNeedTts(true);
                                sentence.setTheType("waitting_tts");
                                sentence.setEnglishDigest(Util.makeSentenceDigest(sentenceEn));
                                    
                                User owner = new User();
                                owner.setId(Constants.SYS_USER_SYS_ID);
                                sentence.setAuthor(owner);
                                sentence.setOwner(owner);
                                    
                                sentenceBo.createEntity(sentence);
                                    
                                sysDbSyncBo.logOperation("INSERT", "sentence", sentence.getId(), JsonUtils.toJson(sentenceBo.toDto(sentence)));
                                logger.info("成功为单词 {} 的释义补充了 AI 例句: {}", spell, sentenceEn);
                            }
                        }
                        
                        Thread.sleep(1500); // 防阿里云限流QPS
                    } catch (Exception innerE) {
                        logger.warn("处理释义项 {} 发生异常: {}", meaningId, innerE.getMessage());
                    }
                }
                logger.info("通用词典例句后台补齐任务全部完成！");
            } catch (Exception e) {
                org.slf4j.LoggerFactory.getLogger(SystemHealthCheckBo.class).error("后台补齐大异常", e);
            }
        }).start();

        // 3. 修复通用词典的数量和序号 (确保即使没有新增单词，也会修复已有的数量不匹配问题)
        try {
            dictBo.fixDictWordSequence(commonDictId);
            dictBo.syncWordCountFromActual(commonDictId);
            fixed.add("已同步通用词典 (ID=0) 的单词序号与数量记录。");
            totalFixed++;
        } catch (Exception e) {
            logger.error("修复通用词典序号/数量时出错", e);
        }

        fixed.add("缺失例句释义项的 AI 后台补齐任务已提交，进度可在服务器日志中查看，补齐会自动同步到客户端更新。");
        return totalFixed + (meaningsWithoutSentences != null ? meaningsWithoutSentences.size() : 0);
    }

    private int fixMissingUserDicts(List<String> fixed) {
        int fixedCount = 0;
        try {
            // 一次性查出所有缺少"生词本"或"已掌握"词书的用户
            String sql = "SELECT u.id, u.user_name, u.nick_name, '生词本' as missing_dict " +
                        "FROM \"user\" u " +
                        "LEFT JOIN dict d ON u.id = d.owner_id AND d.name = '生词本' " +
                        "WHERE d.id IS NULL " +
                        "UNION ALL " +
                        "SELECT u.id, u.user_name, u.nick_name, '已掌握' as missing_dict " +
                        "FROM \"user\" u " +
                        "LEFT JOIN dict d ON u.id = d.owner_id AND d.name = '已掌握' " +
                        "WHERE d.id IS NULL";
            
            List<Object[]> missingDicts = namedParameterJdbcTemplate.query(sql, 
                new MapSqlParameterSource(), 
                (rs, rowNum) -> new Object[]{
                    rs.getString("id"),
                    rs.getString("user_name"),
                    rs.getString("nick_name"),
                    rs.getString("missing_dict")
                }
            );
            
            // 为每个缺失词书的用户创建对应词书
            for (Object[] record : missingDicts) {
                String userId = (String) record[0];
                String userName = (String) record[1];
                String nickName = (String) record[2];
                String missingDict = (String) record[3];
                
                try {
                    User user = userBo.findById(userId);
                    if (user == null) {
                        continue;
                    }
                    
                    // 使用统一的修复逻辑，涵盖词书创建、步骤创建、日志生成和版本升级
                    userDbSyncBo.repairUserBaseData(userId);
                    
                    fixed.add(String.format("为用户 %s (%s, ID: %s) 创建%s", 
                            nickName != null ? nickName : userName, userName, userId, missingDict));
                    fixedCount++;
                } catch (Exception e) {
                    // 记录错误但继续处理其他用户
                    fixed.add(String.format("为用户 %s (ID: %s) 创建%s失败: %s", 
                            userName, userId, missingDict, e.getMessage()));
                }
            }
        } catch (org.springframework.dao.DataAccessException e) {
            org.slf4j.LoggerFactory.getLogger(SystemHealthCheckBo.class).error("自动修复失败", e);
        }
        return fixedCount;
    }

}
