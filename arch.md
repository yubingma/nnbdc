# NNBdc 系统架构文档

## 1. 系统概述

NNBdc 是一个多端背单词应用系统，包含以下主要组件：
- 移动端应用 (Flutter)
- Web 端应用 (Vue.js)
- 后端服务 (Spring Boot)
  注: 以前主要业务逻辑在后端实现, 现在进行了重构, 业务逻辑在前端实现, 后端只做数据备份, 通过同步机制, 把用户数据同步到后端数据库.

## 2. 核心组件

### 2.1 移动端 (Flutter)

#### 主要功能模块
- 用户认证与授权
- 单词学习
- 游戏化学习 (俄罗斯方块游戏)
- 语音识别 (ASR) 和语音合成 (TTS)
- 本地数据缓存

#### 技术栈
- Flutter 框架
- GetX 状态管理
- Provider 状态管理
- Flame 游戏引擎
- Socket.IO 实时通信

### 2.2 Web 端 (Vue.js)

#### 主要功能模块
- 用户管理
- 单词学习
- 学习小组
- 论坛
- 排行榜

#### 技术栈
- Vue.js 2.x
- Vuex 状态管理
- Vue Router 路由管理
- Socket.IO 实时通信
- iView UI 组件库

### 2.3 后端服务 (Spring Boot)

#### 主要功能模块
- 用户认证与授权
- 单词管理
- 游戏系统
- 实时通信
- 数据持久化

#### 技术栈
- Spring Boot
- Spring Security
- Socket.IO
- Swagger API 文档
- JPA/Hibernate

## 3. 核心概念

### 3.1 游戏化学习

系统采用俄罗斯方块游戏作为核心学习机制：
- 单词以方块形式下落
- 玩家需要选择正确的释义
- 支持多人对战模式
- 包含道具系统

### 3.2 实时通信

- 基于 Socket.IO 实现
- 支持多人游戏
- 聊天系统
- 实时排行榜

### 3.3 语音交互

- 语音识别 (ASR)
- 语音合成 (TTS)
- 支持离线语音识别

### 3.4 数据管理

- 本地缓存
- 云端同步
- 学习进度追踪
- 用户数据统计

### 3.5 数据模型

#### 3.5.1 数据对象类型
- **PO (Persistent Object)**
  - 持久化对象
  - 与数据库表结构一一对应，并包含关联数据库对象
  - 包含完整的数据库字段映射
  - 主要用于数据持久化层

- **VO (View Object)**
  - 视图对象
  - 用于前端展示
  - 包含UI所需的字段
  - 包含关联数据对象

- **DTO (Data Transfer Object)**
  - 数据传输对象，每个对象对应一条数据库表记录，不含关联信息
  - 用于前后端数据库同步
  - 优化网络传输效率
  - 隐藏内部实现细节

#### 3.5.2 数据库设计

##### 用户数据库（用户产生的数据）
- 用户基本信息
  - 用户ID、用户名、密码
  - 用户状态、注册时间
  - 用户设置、偏好

- 学习数据
  - 学习进度
  - 单词掌握程度
  - 学习历史记录
  - 错题本

- 社交数据
  - 好友关系
  - 学习小组
  - 论坛帖子
  - 评论记录

##### 系统数据库（所用用户共享的数据）
- 单词库
  - 单词基本信息
  - 释义、例句
  - 词性、音标
  - 难度等级

- 游戏数据
  - 游戏配置
  - 道具系统
  - 排行榜
  - 对战记录

- 系统配置
  - 系统参数
  - 版本信息
  - 更新日志
  - 运营数据

### 3.6 数据流转

1. 数据获取流程
   - 前端请求 → DTO转换 → 服务层处理 → PO持久化 → 数据库

2. 数据展示流程
   - 数据库 → PO查询 → VO转换 → 前端展示

3. 数据同步流程
   - 本地缓存 ↔ 云端同步 ↔ 多端数据一致性

## 4. 系统特点

1. 多端支持：同时支持移动端和 Web 端
2. 游戏化学习：通过游戏提高学习趣味性
3. 实时互动：支持多人对战和社交功能
4. 语音交互：支持语音输入和输出
5. 数据同步：多端数据实时同步
6. 个性化学习：支持自定义学习计划和进度

## 5. Flutter 前端项目结构

### 5.1 目录结构

```
lib/
├── api/           # 网络API接口、DTO/VO定义
├── db/            # 本地数据库相关（表结构、DAO、数据库入口）
│   ├── table.dart         # 所有表结构定义（如User、Level、DictGroup等）
│   ├── dao.dart           # 所有表的DAO（数据访问对象）定义
│   └── database.dart      # 数据库主入口，整合所有表和DAO
├── util/          # 工具类（如同步、加密、格式化等）
├── page/          # 各页面UI
├── global.dart    # 全局变量与配置
└── main.dart      # 应用入口
```

### 5.2 table.dart
- 集中定义所有数据库表的结构，每个表对应一个 Dart 类，继承自 `Table`。
- 例如：
```dart
import 'package:drift/drift.dart';

class Users extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class Levels extends Table {
  TextColumn get id => text()();
  IntColumn get level => integer()();
  @override
  Set<Column> get primaryKey => {id};
}
```
- 字段类型、主键、索引等都在这里声明，便于统一管理。

### 5.3 dao.dart
- 定义所有表的 DAO（数据访问对象），封装对表的增删改查操作。
- 例如：
```dart
import 'package:drift/drift.dart';
import 'database.dart';

@DriftAccessor(tables: [Users])
class UsersDao extends DatabaseAccessor<MyDatabase> with _$UsersDaoMixin {
  UsersDao(MyDatabase db) : super(db);

  Future<List<User>> getAllUsers() => select(users).get();
  Future insertUser(User user) => into(users).insert(user);
}
```
- 每个表通常有一个对应的 DAO 类，提供常用的数据库操作方法。

### 5.4 database.dart
- 数据库主入口，整合所有表结构和 DAO，提供全局唯一的数据库实例。
- 例如：
```dart
import 'package:drift/drift.dart';
import 'table.dart';
import 'dao.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Users, Levels], daos: [UsersDao, LevelsDao])
class MyDatabase extends _$MyDatabase {
  MyDatabase() : super(_openConnection());
  // ... 版本、迁移等
}
```
- 通过 `@DriftDatabase` 注解，将所有表和 DAO 注册到数据库中，自动生成数据库操作代码。

### 5.5 同步流程
- 后端下发的系统数据（如 Level、DictGroup 等）通过 DTO 传输到前端。
- 前端在 `syncSystemDb()` 方法中，解析 DTO 并批量写入本地数据库（通过 DAO）。
- 业务层通过 DAO 查询本地表，获取最新的系统数据。

### 5.6 设计优势
- **解耦**：表结构与业务逻辑分离，便于维护和扩展。
- **类型安全**：Drift 提供类型检查，避免运行时错误。
- **自动生成**：通过 build_runner 自动生成底层 SQL 代码，减少手写 SQL。
- **易于同步**：DTO 与表结构一一对应，便于数据同步和一致性校验。

### 设计原则
- 快速失败原则：让问题尽量明显，尽快暴露

### 核心工作原理
- 系统数据库由管理员产生，首先保存在服务端数据库，并通过同步机制，同步到客户端数据库，以正常使用业务功能
- 用户数据由用户产生，首先保存到客户端，并通过同步机制，同步到服务端数据库作为备份，以同步到用户的其他设备

# 额外说明
本地数据库连接信息:
127.0.0.1:3306
用户名: root 
密码: root
数据库1: bdc (开发用)
数据库2: bdc_test (自动化测试用)



