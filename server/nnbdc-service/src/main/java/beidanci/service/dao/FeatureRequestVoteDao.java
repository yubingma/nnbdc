package beidanci.service.dao;

import org.springframework.stereotype.Repository;

import beidanci.service.po.FeatureRequestVote;

@Repository
public class FeatureRequestVoteDao extends BaseDao<FeatureRequestVote> {
    // JDBC 不再需要 SessionFactory
}

