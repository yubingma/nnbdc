package beidanci.api.model;

public class StudyGroupPostReplyVo extends UuidVo {

    private UserVo user;

    private StudyGroupPostVo studyGroupPost;

    private String content;


    public void setUser(UserVo user) {
        this.user = user;
    }

    public StudyGroupPostVo getStudyGroupPost() {
        return studyGroupPost;
    }

    public void setStudyGroupPost(StudyGroupPostVo studyGroupPost) {
        this.studyGroupPost = studyGroupPost;
    }

    public String getContent() {
        return content;
    }

    public void setContent(String content) {
        this.content = content;
    }

    public UserVo getUser() {
        return user;
    }

}
