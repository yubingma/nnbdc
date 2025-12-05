import 'dart:async';

import 'package:nnbdc/global.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:nnbdc/api/dto.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/config.dart';
import 'package:nnbdc/util/loading_service.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/network_interceptor.dart';
import 'package:retrofit/http.dart' as http;
import 'package:retrofit/retrofit.dart';

part 'api.g.dart';

// 自定义 HTTP 客户端适配器已移除，使用 Dio 默认的自动解压

class Api {
  static RestClient? _client;
  static final LoadingService loadingService = LoadingService();
  static bool disableAutoLoading = false;

// 手动解压相关代码已移除，使用 Dio 自动解压

  static void setLoadingDisabled(bool disable) {
    disableAutoLoading = disable;
  }

  static RestClient get client {
    _client ??= initClient();
    return _client!;
  }

  static RestClient initClient() {
    Dio dio;
    if (PlatformUtils.isWeb) {
      dio = Dio(BaseOptions(
          connectTimeout: Duration(milliseconds: 5000),
          sendTimeout: Duration(milliseconds: 300000), // 5分钟
          receiveTimeout: Duration(milliseconds: 300000))); // 浏览器会自动协商压缩，禁止手动设置 Accept-Encoding
      (dio.httpClientAdapter as dynamic).withCredentials = true;
    } else {
      dio = Dio(BaseOptions(
          connectTimeout: Duration(milliseconds: 5000),
          sendTimeout: Duration(milliseconds: 300000), // 5分钟
          receiveTimeout: Duration(milliseconds: 300000))); // 由 Dio/底层库处理压缩
      var cookieJar = CookieJar();
      dio.interceptors.add(CookieManager(cookieJar));
    }


    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        // 简化的请求日志，避免重复构建
        if (options.path.contains('getDictResById.do')) {
          Global.logger.d('🔄 getDictResById 请求开始: ${options.uri}');
          
          // 清理无效的 Cookie 头
          if (options.headers.containsKey('cookie') &&
              options.headers['cookie'] == null) {
            options.headers.remove('cookie');
          }
        } else {
          Global.logger.d('📤 请求: ${options.path}');
        }

        options.onReceiveProgress = (received, total) {
          if (options.path.contains('getDictResById.do')) {
            _DownloadProgress.update(options.path, received, total);
          }
        };
        handler.next(options);
      },
      onResponse: (response, handler) async {
        if (response.requestOptions.path.contains('getDictResById.do')) {
          // 简化的响应日志，只记录关键信息
          String? contentLength = response.headers.value('content-length');
          String? contentEncoding = response.headers.value('content-encoding');
          
          if (contentLength != null) {
            double sizeInMB = int.parse(contentLength) / (1024 * 1024);
            Global.logger.d('📊 响应大小: ${sizeInMB.toStringAsFixed(2)}MB, 压缩: ${contentEncoding ?? "无"}');
          }
          
          Global.logger.d('✅ 响应数据类型: ${response.data.runtimeType}');
        }
        handler.next(response);
      },
    ));

    // 添加网络检测拦截器（最先执行）
    dio.interceptors.add(NetworkInterceptor());
    dio.interceptors.add(CustomInterceptors());
    final client = RestClient(dio, baseUrl: Config.serviceUrl);
    return client;
  }
}

class CustomInterceptors extends Interceptor {
  final LoadingService _loadingService = LoadingService();

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    if (Api.disableAutoLoading) {
      return super.onRequest(options, handler);
    }

    _loadingService.progressColor = Colors.yellow;
    _loadingService.backgroundColor = Colors.blue;
    _loadingService.indicatorColor = Colors.yellow;
    _loadingService.textColor = Colors.yellow;
    _loadingService.maskColor = Colors.transparent;
    _loadingService.userInteractions = false;
    _loadingService.dismissOnTap = false;
    _loadingService.indicatorSize = 45.0;
    _loadingService.radius = 10.0;

    await _loadingService.show(status: 'loading...');
    return super.onRequest(options, handler);
  }

  @override
  void onResponse(response, ResponseInterceptorHandler handler) async {
    if (!Api.disableAutoLoading) {
      _loadingService.dismiss();
    }
    
    // 简化的响应日志
    try {
      String path = response.requestOptions.path;
      int statusCode = response.statusCode ?? 0;
      
      // 只对关键接口记录详细日志
      if (path.contains('getDictResById.do') || path.contains('getUserDbLogsFromVersion.do')) {
        Global.logger.i('📥 收到完整应答 - $path, 状态码: $statusCode');
        
        // 记录响应大小（如果还没有记录过）
        if (path.contains('getUserDbLogsFromVersion.do')) {
          String? contentLength = response.headers.value('content-length');
          if (contentLength != null) {
            double sizeInMB = int.parse(contentLength) / (1024 * 1024);
            Global.logger.d('📊 响应大小: ${sizeInMB.toStringAsFixed(2)}MB');
          }
        }
      }
      
    } catch (e) {
      Global.logger.w('⚠️ 记录响应日志时出错: $e');
    }
    
    return super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (!Api.disableAutoLoading) {
      _loadingService.dismiss();
    }

    if (err.response?.statusCode == 401) {
      ToastUtil.error('会话超时，请重新登录');
      Get.toNamed("/email_login");
    } else if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.sendTimeout) {
      // 超时错误处理
      if (err.requestOptions.path.contains('getDictResById.do')) {
        ToastUtil.error('词典数据下载超时，请检查网络连接或稍后重试');
        Global.logger.e('❌ getDictResById 接口超时: ${err.message}');
        Global.logger.e('❌ 超时类型: ${err.type}');
        Global.logger.e('❌ 请求路径: ${err.requestOptions.path}');
        Global.logger.e('❌ 实际超时配置:');
        Global.logger.e(
            '   - connectTimeout: ${err.requestOptions.connectTimeout?.inSeconds}秒');
        Global.logger.e(
            '   - sendTimeout: ${err.requestOptions.sendTimeout?.inSeconds}秒');
        Global.logger.e(
            '   - receiveTimeout: ${err.requestOptions.receiveTimeout?.inSeconds}秒');
      } else {
        ToastUtil.error('请求超时，请检查网络连接');
      }
    } else {
      // 非超时/未授权的其他网络错误（如5xx），避免在拦截器里直接弹Toast，交由各调用方统一错误处理
      Global.logger.e('网络错误: ${err.message}', error: err, stackTrace: err.stackTrace);
    }
    return super.onError(err, handler);
  }
}

/// 下载进度类，用于更新下载进度条
class _DownloadProgress {
  static final Map<String, Map<String, dynamic>> _progressMap = {};
  static final Map<String, List<Function(int, int)>> _listeners = {};

  /// 更新指定资源的下载进度
  static void update(String resourceId, int received, int total) {
    _progressMap[resourceId] = {
      'received': received,
      'total': total,
    };

    // 减少监听器通知频率，只在关键节点通知
    if (received % (1024 * 1024) == 0 || received >= total) { // 每1MB通知一次
      _notifyListeners(resourceId, received, total);
    }
  }

  /// 获取指定资源的下载进度
  static Map<String, dynamic>? getProgress(String resourceId) {
    return _progressMap[resourceId];
  }

  /// 清除指定资源的下载进度
  static void clear(String resourceId) {
    _progressMap.remove(resourceId);
  }

  /// 清除所有资源的下载进度
  static void clearAll() {
    _progressMap.clear();
  }

  // 监听器管理
  static void addListener(String resourceId, Function(int, int) listener) {
    if (!_listeners.containsKey(resourceId)) {
      _listeners[resourceId] = [];
    }
    _listeners[resourceId]!.add(listener);
  }

  /// 移除下载进度监听器
  static void removeListener(String resourceId, Function(int, int) listener) {
    if (_listeners.containsKey(resourceId)) {
      _listeners[resourceId]!.remove(listener);
      if (_listeners[resourceId]!.isEmpty) {
        _listeners.remove(resourceId);
      }
    }
  }

  /// 通知所有监听者
  static void _notifyListeners(String resourceId, int received, int total) {
    if (_listeners.containsKey(resourceId)) {
      for (var listener in _listeners[resourceId]!) {
        listener(received, total);
      }
    }
  }
}

/// 公共的下载进度管理器
class DownloadProgressManager {
  /// 添加下载进度监听器
  static void addListener(String resourceId, Function(int, int) listener) {
    _DownloadProgress.addListener(resourceId, listener);
  }

  /// 移除下载进度监听器
  static void removeListener(String resourceId, Function(int, int) listener) {
    _DownloadProgress.removeListener(resourceId, listener);
  }

  /// 获取指定资源的下载进度
  static Map<String, dynamic>? getProgress(String resourceId) {
    return _DownloadProgress.getProgress(resourceId);
  }

  /// 清除指定资源的下载进度
  static void clear(String resourceId) {
    _DownloadProgress.clear(resourceId);
  }

  /// 清除所有资源的下载进度
  static void clearAll() {
    _DownloadProgress.clearAll();
  }
}

@RestApi()
abstract class RestClient {
  factory RestClient(
    Dio dio, {
    String baseUrl,
    ParseErrorLogger? errorLogger,
  }) = _RestClient;

  @PUT("/checkUser.do")
  @FormUrlEncoded()
  Future<Result> checkUser(
      @Field("checkBy") String checkBy,
      @Field("email") String? email,
      @Field("userName") String? userName,
      @Field("password") String password,
      @Field("clientType") String clientType,
      @Field("clientVersion") String clientVersion);

  @GET("/getPwd.do")
  Future<Result> getPwd(@Query("email") String email);

  // 邮箱验证码API
  @POST("/sendEmailCode.do")
  @FormUrlEncoded()
  Future<Result> sendEmailCode(
      @Field("email") String email,
      @Field("type") String type);

  @POST("/loginByEmailCode.do")
  @FormUrlEncoded()
  Future<Result> loginByEmailCode(
      @Field("email") String email,
      @Field("code") String code,
      @Field("clientType") String clientType,
      @Field("clientVersion") String clientVersion);

  // 微信登录API
  @POST("/loginByWechat.do")
  @FormUrlEncoded()
  Future<Result> loginByWechat(
      @Field("code") String code,
      @Field("clientType") String clientType,
      @Field("clientVersion") String clientVersion);

  @POST("/sendAdvice.do")
  @FormUrlEncoded()
  Future<Result> sendAdvice(
      @Field("content") String content, 
      @Field("clientType") String clientType,
      @Query("userId") String userId);

  @GET("/res/getDictResById.do")
  Future<Result<DictRes>> getDictResById(@Query("dictId") String dictId);

  @GET("/getGameHallData.do")
  Future<GetGameHallDataResult> getGameHallData();


  @POST("/saveSentenceChinese.do")
  @FormUrlEncoded()
  Future<Result<SentenceVo>> saveSentenceChinese(
      @Field("sentenceId") String sentenceId,
      @Field("chinese") String chinese,
      @Query("currWord") String? currWord);

  @POST("/uploadWordImg.do")
  @FormUrlEncoded()
  Future<Result<WordImageDto>> uploadWordImg(@Field("wordId") String wordId,
      @Field("imgBase64String") String imgBase64String, @Field("userId") String userId);

  @POST("/saveErrorReport.do")
  @FormUrlEncoded()
  Future<Result<String>> saveErrorReport(
      @Field("word") String word, @Field("content") String content, @Field("clientType") String clientType, @Query("userId") String? userId);

  @POST("/saveSentence.do")
  @FormUrlEncoded()
  Future<Result<SentenceVo>> saveSentence(
      @Field("english") String english,
      @Field("chinese") String chinese,
      @Field("wordId") String wordId,
      @Field("payCowdung") int payCowdung,
      @Query("currWord") String? currWord,
      @Query("userId") String userId);

  @PUT("/handSentenceChinese.do")
  Future<Result<int>> handSentenceUgcChinese(
      @Query("id") String itemId, @Query("currWord") String? currWord);

  @PUT("/footSentenceChinese.do")
  Future<Result<int>> footSentenceUgcChinese(
      @Query("id") String itemId, @Query("currWord") String? currWord);

  @PUT("/handSentence.do")
  @FormUrlEncoded()
  Future<Result> handSentence(
      @Field("id") String id, @Query("currWord") String? currWord, @Query("userId") String userId);

  @PUT("/footSentence.do")
  @FormUrlEncoded()
  Future<Result> footSentence(
      @Field("id") String id, @Query("currWord") String? currWord, @Query("userId") String userId);

  @PUT("/handImage.do")
  @FormUrlEncoded()
  Future<Result<int>> handWordImage(@Field("id") String id);

  @PUT("/footImage.do")
  @FormUrlEncoded()
  Future<Result<int>> footWordImage(@Field("id") String id);

  @DELETE("/deleteImage.do")
  Future<Result> deleteWordImage(@Query("id") String id, @Query("userId") String userId);

  @DELETE("/deleteSentenceChinese.do")
  Future<Result> deleteSentenceChinese(
      @Query("id") String itemId, @Query("currWord") String? currWord);

  @DELETE("/unRegister.do")
  Future<Result> unRegister(@Query("userId") String userId);

  @DELETE("/deleteSentence.do")
  Future<Result> deleteSentence(
      @Query("id") String rawWordId, @Query("currWord") String? currWord, @Query("userId") String userId);

  @GET("/getMsgCounts.do")
  Future<Result<Pair<int, int>>> getMsgCounts(@Query("userId") String userId);

  @GET("/getLastestMsgsBetweenUserAndSys.do")
  Future<List<MsgVo>> getLastestMsgsBetweenUserAndSys(
      @Query("user") String userId, @Query("msgCount") int msgCount);

  @PUT("/setMsgsAsViewed.do")
  @FormUrlEncoded()
  Future<Result> setMsgsAsViewed(
      @Field("msgIds") List<String> msgIds, @Field("userId") String userId);

  @GET("/getAllAdviceMessages.do")
  Future<List<MsgVo>> getAllAdviceMessages();

  @POST("/replyAdvice.do")
  @FormUrlEncoded()
  Future<Result> replyAdvice(
      @Field("content") String content,
      @Field("toUserId") String toUserId,
      @Field("adminUserId") String adminUserId);

  @GET("/getUserDbLogsFromVersion.do")
  Future<Result<List<UserDbLogDto>>> getDbLogsFromVersion(
      @Query("fromVersion") int fromVersion,
      @Query("userId") String userId);

  @POST("/syncUserDb2Back.do")
  @http.Headers(<String, dynamic>{
    "Content-Type": "application/json",
  })
  Future<Result<int>> syncUserDb(
      @Query("expectedServerDbVersion") int expectedServerDbVersion,
      @Query("userId") String userId,
      @Body() List<UserDbLogDto> logs);



  @GET("/getSystemDbVersion.do")
  Future<Result<int>> getSystemDbVersion();


  @GET("/getSysDbVersion.do")
  Future<Result<int>> getSysDbVersion();

  @GET("/getNewSysDbLogs.do")
  Future<Result<List<SysDbLogDto>>> getNewSysDbLogs(
    @Query("fromVersion") int fromVersion
  );


  /// 记录用户登录操作
  @POST('/recordLogin.do')
  Future<Result<bool>> recordLogin(@Query('remark') String? remark);

  @GET("/getUserDbVersion.do")
  Future<Result<int>> getUserDbVersion(@Query("userId") String userId);

  @GET("/getUserRank.do")
  Future<Result<int>> getUserRank(@Query("userId") String userId);

  @GET("/getSystemDictsWithStats.do")
  Future<Result<List<DictStatsVo>>> getSystemDictsWithStats();

  @GET("/getDictStats.do")
  Future<Result<DictStatsVo>> getDictStats(@Query("dictId") String dictId);

  @POST("/updateSystemDict.do")
  @FormUrlEncoded()
  Future<Result<String>> updateSystemDict(
      @Field("dictId") String dictId,
      @Field("name") String name,
      @Field("isReady") bool isReady,
      @Field("visible") bool visible,
      @Field("popularityLimit") int? popularityLimit);

  @POST("/updateDictWord.do")
  @FormUrlEncoded()
  Future<Result<String>> updateDictWord(
      @Field("wordId") String wordId,
      @Field("spell") String spell,
      @Field("shortDesc") String? shortDesc,
      @Field("longDesc") String? longDesc,
      @Field("pronounce") String? pronounce,
      @Field("americaPronounce") String? americaPronounce,
      @Field("britishPronounce") String? britishPronounce,
      @Field("popularity") int? popularity);

  @POST("/removeWordFromDict.do")
  @FormUrlEncoded()
  Future<Result<String>> removeWordFromDict(
      @Field("dictId") String dictId,
      @Field("wordId") String wordId);

  // 系统健康检查相关API
  @GET("/admin/checkSystemDictIntegrity.do")
  Future<Result<SystemHealthCheckResult>> checkSystemDictIntegrity();

  @GET("/admin/checkUserDictIntegrity.do")
  Future<Result<SystemHealthCheckResult>> checkUserDictIntegrity();

  @GET("/admin/checkLearningProgress.do")
  Future<Result<SystemHealthCheckResult>> checkLearningProgress();

  @GET("/admin/checkDbVersionConsistency.do")
  Future<Result<SystemHealthCheckResult>> checkDbVersionConsistency();

  @GET("/admin/checkCommonDictIntegrity.do")
  Future<Result<SystemHealthCheckResult>> checkCommonDictIntegrity();

  @POST("/admin/autoFixSystemIssues.do")
  @FormUrlEncoded()
  Future<Result<SystemHealthFixResult>> autoFixSystemIssues(
      @Field("issueTypes") List<String> issueTypes);

  // 用户管理相关API
  @GET("/admin/searchUsers.do")
  Future<Result<PagedResults<UserVo>>> searchUsers(
      @Query("keyword") String? keyword,
      @Query("pageNo") int pageNo,
      @Query("pageSize") int pageSize,
      @Query("filterType") int? filterType);

  @POST("/admin/updateAdminPermission.do")
  @FormUrlEncoded()
  Future<Result<String>> updateAdminPermission(
      @Field("userId") String userId,
      @Field("isAdmin") bool? isAdmin,
      @Field("isSuperAdmin") bool? isSuperAdmin,
      @Field("isInputor") bool? isInputor);

  @DELETE("/admin/deleteUser.do")
  Future<Result<String>> deleteUser(@Query("userId") String userId);

  // CDN管理相关API
  @POST("/admin/refreshCdnCache.do")
  @FormUrlEncoded()
  Future<Result<String>> refreshCdnCache(
      @Field("urls") String urls,
      @Field("objectType") String objectType);

  @GET("/admin/getCdnRefreshUrls.do")
  Future<Result<JsonMap>> getCdnRefreshUrls();

  @POST("/admin/saveCdnRefreshUrls.do")
  @FormUrlEncoded()
  Future<Result<String>> saveCdnRefreshUrls(
      @Field("fileUrls") String fileUrls,
      @Field("dirUrls") String dirUrls);

  // 阿里云资源查询相关API
  @GET("/admin/queryAliyunBalance.do")
  Future<Result<JsonMap>> queryAliyunBalance();

  @GET("/admin/queryAliyunResourcePackages.do")
  Future<Result<JsonMap>> queryAliyunResourcePackages();

  // 需求墙相关API
  @GET("/getAllFeatureRequests.do")
  Future<List<FeatureRequestVo>> getAllFeatureRequests();

  @POST("/createFeatureRequest.do")
  @FormUrlEncoded()
  Future<Result<FeatureRequestVo>> createFeatureRequest(
      @Field("title") String title,
      @Field("content") String content,
      @Field("userId") String userId);

  @POST("/voteFeatureRequest.do")
  @FormUrlEncoded()
  Future<Result> voteFeatureRequest(
      @Field("requestId") String requestId,
      @Field("userId") String userId);

  @GET("/hasUserVoted.do")
  Future<Result<bool>> hasUserVoted(
      @Query("requestId") String requestId,
      @Query("userId") String userId);

  @PUT("/updateFeatureRequestStatus.do")
  @FormUrlEncoded()
  Future<Result> updateFeatureRequestStatus(
      @Field("requestId") String requestId,
      @Field("status") String status,
      @Field("adminUserId") String adminUserId);

  // 需求墙举报相关API
  @POST("/saveFeatureRequestReport.do")
  @FormUrlEncoded()
  Future<Result<String>> saveFeatureRequestReport(
      @Field("requestId") String requestId,
      @Field("content") String content,
      @Field("userId") String userId);

  @GET("/getAllFeatureRequestReports.do")
  Future<List<FeatureRequestReportVo>> getAllFeatureRequestReports();
}
