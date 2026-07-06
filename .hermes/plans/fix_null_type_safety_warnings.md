# 修复 Java 代码中的 Null type safety 编译警告

## 影响范围
- Flutter: 否
- Server: 是，涉及 `beidanci.service` 包下的 BO/Controller/Socket 状态类
- 音频/ASR: 否

## Task 分解

### Task 1: 修复 DictGroupBo 中的 warnings
- 文件: `server/nnbdc-service/src/main/java/beidanci/service/bo/DictGroupBo.java`
- 变更: 将 `DictGroup::getId` 与 `Dict::getId` 方法引用替换为 Lambda 表达式
- 验证: `cd server && mvn compile -q`

### Task 2: 修复 GameHallBo 中的 warning
- 文件: `server/nnbdc-service/src/main/java/beidanci/service/bo/GameHallBo.java`
- 变更: 将 `Word::getId` 方法引用替换为 Lambda 表达式
- 验证: `cd server && mvn compile -q`

### Task 3: 修复 HallGroupBo 中的 warnings
- 文件: `server/nnbdc-service/src/main/java/beidanci/service/bo/HallGroupBo.java`
- 变更: 将 `HallGroup::getId` 与 `DictGroup::getId` 方法引用替换为 Lambda 表达式
- 验证: `cd server && mvn compile -q`

### Task 4: 修复 UserStudyStepBo 中的 warning
- 文件: `server/nnbdc-service/src/main/java/beidanci/service/bo/UserStudyStepBo.java`
- 变更: 将 `UserStudyStep::getStudyStep` 方法引用替换为 Lambda 表达式
- 验证: `cd server && mvn compile -q`

### Task 5: 修复 DictImportController 中的 warning
- 文件: `server/nnbdc-service/src/main/java/beidanci/service/controller/DictImportController.java`
- 变更: 将 `File::isDirectory` 方法引用替换为 Lambda 表达式
- 验证: `cd server && mvn compile -q`

### Task 6: 修复 GameController 中的 warning
- 文件: `server/nnbdc-service/src/main/java/beidanci/service/controller/GameController.java`
- 变更: 将 `HallGroup::getDisplayOrder` 方法引用替换为 Lambda 表达式
- 验证: `cd server && mvn compile -q`

### Task 7: 修复 GameOverProcessor 中的 warning
- 文件: `server/nnbdc-service/src/main/java/beidanci/service/socket/system/game/russia/state/GameOverProcessor.java`
- 变更: 将 `UserGameData::isExercise` 方法引用替换为 Lambda 表达式
- 验证: `cd server && mvn compile -q`

### Task 8: 修复 ReadyState 中的 warnings
- 文件: `server/nnbdc-service/src/main/java/beidanci/service/socket/system/game/russia/state/ReadyState.java`
- 变更: 将 `TimerTask::cancel` 方法引用替换为 Lambda 表达式
- 验证: `cd server && mvn compile -q`
