package beidanci.api.model;

import java.util.List;

public class UserBaseDataVo {
    private DictDto rawDict;
    private DictDto masteredDict;
    private List<UserStudyStepDto> studySteps;

    public UserBaseDataVo() {
    }

    public UserBaseDataVo(DictDto rawDict, DictDto masteredDict, List<UserStudyStepDto> studySteps) {
        this.rawDict = rawDict;
        this.masteredDict = masteredDict;
        this.studySteps = studySteps;
    }

    public DictDto getRawDict() {
        return rawDict;
    }

    public void setRawDict(DictDto rawDict) {
        this.rawDict = rawDict;
    }

    public DictDto getMasteredDict() {
        return masteredDict;
    }

    public void setMasteredDict(DictDto masteredDict) {
        this.masteredDict = masteredDict;
    }

    public List<UserStudyStepDto> getStudySteps() {
        return studySteps;
    }

    public void setStudySteps(List<UserStudyStepDto> studySteps) {
        this.studySteps = studySteps;
    }
}
