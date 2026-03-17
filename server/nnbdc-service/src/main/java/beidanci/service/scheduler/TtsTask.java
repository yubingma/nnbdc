package beidanci.service.scheduler;

import java.io.File;
import java.io.FileOutputStream;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import beidanci.service.bo.AiBo;
import beidanci.service.bo.SentenceBo;
import beidanci.service.bo.SysDbSyncBo;
import beidanci.service.po.Sentence;

@Component
public class TtsTask {
    private static final Logger log = LoggerFactory.getLogger(TtsTask.class);

    @Autowired
    private NamedParameterJdbcTemplate jdbcTemplate;

    @Autowired
    private SentenceBo sentenceBo;

    @Autowired
    private SysDbSyncBo sysDbSyncBo;

    @Autowired
    private AiBo aiBo;

    // 定时检查 waitting_tts 的例句，每10秒执行一次
    @Scheduled(fixedDelay = 10000)
    public void generateSentenceTts() {
        String sql = "SELECT * FROM sentence WHERE need_tts = true OR the_type = 'waitting_tts' LIMIT 10";
        List<Sentence> sentences = jdbcTemplate.query(sql, new MapSqlParameterSource(),
                new beidanci.service.dao.EntityRowMapper<>(Sentence.class));

        if (sentences.isEmpty()) {
            return;
        }

        for (Sentence sentence : sentences) {
            log.info("开始为例句生成 TTS: {} (英语: {})", sentence.getId(), sentence.getEnglish());
            try {
                // 生成语音
                byte[] audioData = aiBo.generateSpeech(sentence.getEnglish());
                if (audioData != null && audioData.length > 0) {
                    // 保存到文件系统
                    saveAudioFile(sentence.getEnglishDigest(), audioData);

                    // 更新数据库状态
                    sentence.setNeedTts(false);
                    sentence.setTheType(Sentence.TTS);
                    sentenceBo.updateEntity(sentence);

                    // 记录一下系统同步日志
                    sysDbSyncBo.logOperation("UPDATE", "sentence", sentence.getId(), beidanci.service.util.JsonUtils.toJson(sentenceBo.toDto(sentence)));
                    log.info("例句 TTS 生成成功并保存: {}", sentence.getId());
                } else {
                    log.error("TTS 生成失败，获得空的音频数据: {}", sentence.getId());
                }
            } catch (Exception e) {
                log.error("TTS 生成过程发生异常: " + sentence.getId(), e);
            }
        }
    }

    private void saveAudioFile(String englishDigest, byte[] audioData) throws Exception {
        if (englishDigest == null || englishDigest.trim().isEmpty()) {
            log.error("英语原文的摘要不存在，无法保存 TTS");
            return;
        }

        File dir = new File("/var/nnbdc/sound/sentence");
        if (!dir.exists()) {
            dir.mkdirs();
        }

        File file = new File(dir, englishDigest + ".mp3");
        try (FileOutputStream fos = new FileOutputStream(file)) {
            fos.write(audioData);
            fos.flush();
        }
    }
}
