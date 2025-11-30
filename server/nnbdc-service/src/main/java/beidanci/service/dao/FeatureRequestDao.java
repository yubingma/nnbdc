package beidanci.service.dao;

import org.springframework.stereotype.Repository;

import beidanci.service.po.FeatureRequest;

@Repository
public class FeatureRequestDao extends BaseDao<FeatureRequest> {
    // JDBC 不再需要 SessionFactory
}

