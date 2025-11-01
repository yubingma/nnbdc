package beidanci.service.dao;

import javax.annotation.Resource;

import org.hibernate.Session;
import org.hibernate.SessionFactory;
import org.springframework.stereotype.Repository;

import beidanci.service.po.FeatureRequestVote;

@Repository
public class FeatureRequestVoteDao extends BaseDao<FeatureRequestVote> {
    
    @Resource(name = "sessionFactory")
    private SessionFactory sessionFactory;
    
    public Session getSession() {
        return sessionFactory.getCurrentSession();
    }
}

