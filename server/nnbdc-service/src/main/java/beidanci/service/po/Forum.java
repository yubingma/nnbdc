package beidanci.service.po;

import java.util.List;

import javax.persistence.CascadeType;
import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.FetchType;
import javax.persistence.JoinColumn;
import javax.persistence.JoinTable;
import javax.persistence.ManyToMany;
import javax.persistence.OneToMany;
import javax.persistence.Table;

@Entity
@Table(name = "forum")
public class Forum extends UuidPo {

    @Column(name = "name", nullable = false)
    private String name;

    @ManyToMany(cascade = {CascadeType.PERSIST, CascadeType.REMOVE, CascadeType.MERGE})
    @JoinTable(name = "forum_and_manager_link", joinColumns = @JoinColumn(name = "forumId"), inverseJoinColumns = @JoinColumn(name = "userId"))
    private List<User> managers;

    @OneToMany(cascade = {CascadeType.PERSIST, CascadeType.REMOVE,
            CascadeType.MERGE}, mappedBy = "forum", fetch = FetchType.LAZY)
    private List<ForumPost> forumPosts;

    // Constructors

    /**
     * default constructor
     */
    public Forum() {
    }

    /**
     * minimal constructor
     */
    public Forum(String id, String name) {
        this.id = id;
        this.name = name;
    }

    /**
     * full constructor
     */
    public Forum(String id, String name, List<User> managers, List<ForumPost> forumPosts) {
        this.id = id;
        this.name = name;
        this.managers = managers;
        this.forumPosts = forumPosts;
    }

    // Property accessors

    public String getName() {
        return this.name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public List<User> getManagers() {
        return this.managers;
    }

    public void setManagers(List<User> managers) {
        this.managers = managers;
    }

    public List<ForumPost> getForumPosts() {
        return this.forumPosts;
    }

    public void setForumPosts(List<ForumPost> forumPosts) {
        this.forumPosts = forumPosts;
    }

}
