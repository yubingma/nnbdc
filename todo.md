
10. 创意玩法：russia对战新增干扰道具「形近障眼法」（使对方答题混淆项全部来自形近词释义，详见 design/ideas.html IDEA #002）
11. UGC冷启动AI评分与新星展位（打破点赞马太效应，详见 design/ideas.html IDEA #003）
12. 语境辨义与语音识义：基于「释义-例句」严格绑定资产开发情境题型与对战玩法（详见 design/ideas.html IDEA #004）
13. 【数据修复·待执行】重复计分脏数据清理：先发版客户端闸门 → 执行 devops/repair_duplicate_learning_log.sql（删 134003 条重复日志 / 修 5900 个词 memory）
14. 【掌握口径统一·方案A】把「stability < 掌握线 = 学习中」的代理判定（约 14 处：learning_service/dao/word_bo/desk_section/word_list_extensions 等）改为以用户已掌握记录为单一真理来源；进度条 getWordProgressMax 保留阈值刻度。目标：S∈[120,180) 的 3667 词不再隐身、「取消掌握」后能回到学习中（原先的「批量补录」方案作废——已掌握是用户可编辑词书，不得越权写入）
