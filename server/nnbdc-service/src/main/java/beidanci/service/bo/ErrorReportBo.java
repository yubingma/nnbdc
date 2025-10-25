package beidanci.service.bo;

import javax.annotation.PostConstruct;

import beidanci.api.Result;
import beidanci.service.dao.BaseDao;
import beidanci.service.po.ErrorReport;
import beidanci.service.po.User;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Timestamp;
import java.util.Date;
import java.util.List;

@Service
@Transactional(rollbackFor = Throwable.class)
public class ErrorReportBo extends BaseBo<ErrorReport> {
    @Autowired
    UserBo userBo;

    @Autowired
    MsgBo msgBo;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<ErrorReport>() {
        });
    }

    public List<ErrorReport> findByWordSpell(String spell) {
        ErrorReport exam = new ErrorReport();
        exam.setWord(spell);
        return baseDao.queryAll(getSession(), exam, null, null);
    }

    public Result<String> saveErrorReport(String spell, String content, String userId) {
        User user = userBo.findById(userId);

        if (content.trim().length() == 0) {
            return Result.fail("内容不能为空");
        }

        // 保存单词报错内容
        ErrorReport errorReport = new ErrorReport();
        errorReport.setWord(spell);
        errorReport.setContent(content);
        errorReport.setCreateTime(new Timestamp(new Date().getTime()));
        errorReport.setUser(user);
        errorReport.setFixed(false);
        createEntity(errorReport);

        String advice = String.format("单词报错，单词[%s], 报错内容[%s]", spell, content);
        msgBo.sendAdvice(advice, user);

        return Result.success(String.valueOf(errorReport.getId()), content);
    }

}
