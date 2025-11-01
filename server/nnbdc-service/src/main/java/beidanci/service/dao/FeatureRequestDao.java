package beidanci.service.dao;

import javax.annotation.Resource;

import org.hibernate.Session;
import org.hibernate.SessionFactory;
import org.springframework.stereotype.Repository;

import beidanci.service.po.FeatureRequest;

@Repository
public class FeatureRequestDao extends BaseDao<FeatureRequest> {
    
    @Resource(name = "sessionFactory")
    private SessionFactory sessionFactory;
    
    public Session getSession() {
        return sessionFactory.getCurrentSession();
    }
}

