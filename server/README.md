# 项目简介
欢迎到项目主页 http://www.nnbdc.com 进行体验。
# 运行源码需要的先决条件：
* JDK 1.8+
* mysql 5.7+
* tomcat 7+
* maven

开发计划：
2020-01-04：RxJava重构
2020-01-04：例句可投票（发音，文本）,后台可根据票数实时调整例句的先后
2020-01-05: 所有类型的例句均可由用户提供翻译
Global.getSentenceChineseBO().getSentenceChineses（）性能增强

#单词书取词的核心逻辑：
select wordId, count(0), min(seq) as minIndex, max(seq) as maxIndex, max(ld.isPrivileged) as is_privileged
from dict_word dw left join learning_dict ld on dw.dictId = ld.dictId   left join dict d on dw.dictId  = d.id
where ld.userId = 21387
and (ld.currentWordSeq is null or ld.currentWordSeq < d.wordCount )
and (dw.seq > ld.currentWordSeq or ld.currentWordSeq is null)
and (ld.fetchMastered  = 1 or not exists (select 0 from mastered_word mw where mw.userId=21387 and mw.wordId=dw.wordId) )
and not exists (select 0 from learning_word lw where lw.userId=21387 and lw.wordId=dw.wordId)
group by wordId order by is_privileged desc, minIndex asc  limit 20;

#更新学习中词书当前位置的核心逻辑
select * from learning_dict ld where userId =132;
select dw.dictId, min(seq) from dict_word dw left join learning_dict ld on dw.dictId =ld.dictId  left join dict d on dw.dictId  = d.id
where ld.userId =132
and ld.currentWordSeq < d.wordCount
and (dw.seq > ld.currentWordSeq  or  ld.currentWordSeq is null)
and not exists (select 0 from learning_word lw where lw.userId =132 and lw.wordId=dw.wordId)  
and not exists (select 0 from mastered_word mw where mw.userId=132 and mw.wordId=dw.wordId)
group by dw.dictId ;