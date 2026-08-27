import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:fl_clash/xboard/config/xboard_config.dart';
import 'package:fl_clash/xboard/config/utils/config_file_loader.dart';
import 'package:flutter_v2board_sdk/flutter_v2board_sdk.dart';
// 已从core/utils导出
import 'package:fl_clash/xboard/core/core.dart';
import 'package:fl_clash/xboard/infrastructure/infrastructure.dart';
import 'package:fl_clash/xboard/infrastructure/http/user_agent_config.dart';
import 'concurrent_subscription_service.dart';

// 初始化文件级日志器
final _logger = FileLogger('encrypted_subscription_service.dart');

/// 加密订阅获取服务
/// 
/// 负责从XBoard加密端点获取订阅数据并解密
class EncryptedSubscriptionService {
  static const Duration requestTimeout = Duration(seconds: 30);
  static const int maxRetries = 3;

  /// 从登录数据中获取加密订阅（推荐方法）
  /// 
  /// [preferEncrypt] 是否优先使用加密端点，默认true
  /// [enableRace] 是否启用订阅URL竞速，默认true
  /// 
  /// 返回解密后的Clash配置内容
  static Future<SubscriptionResult> getEncryptedSubscriptionFromLogin({
    bool preferEncrypt = true,
    bool enableRace = true,
  }) async {
    try {
      _logger.info('从登录数据获取加密订阅');

      // 1. 获取订阅信息（注意：这里获取的是订阅数据，不是Auth Token）
      final subscriptionData = await V2BoardSDK.instance.subscription
          .getSubscription();

      final subscribeUrl = subscriptionData.subscribeUrl;
      if (subscribeUrl == null || subscribeUrl.isEmpty) {
        return SubscriptionResult.failure('订阅URL为空');
      }

      _logger.info('获取到订阅URL: $subscribeUrl');

      // 2. 从订阅URL中提取订阅token（不是Auth Token！）
      final token = _extractTokenFromSubscriptionUrl(subscribeUrl);
      
      if (token == null || token.isEmpty) {
        return SubscriptionResult.failure('无法从订阅URL中提取token: $subscribeUrl');
      }

      _logger.info('从订阅URL提取到订阅token: ${token.substring(0, 8)}...');

      // 3. 使用订阅token获取加密订阅
      return await getEncryptedSubscription(
        token, 
        preferEncrypt: preferEncrypt,
        enableRace: enableRace,
      );

    } catch (e) {
      _logger.error('从登录数据获取订阅失败', e);
      return SubscriptionResult.failure('从登录数据获取订阅失败: $e');
    }
  }

  /// 从订阅URL中提取token
  /// 
  /// 支持多种格式：
  /// - https://domain.com/s/abc123...
  /// - https://domain.com/api/v1/client/subscribe?token=abc123...
  static String? _extractTokenFromSubscriptionUrl(String url) {
    try {
      final uri = Uri.parse(url);
      
      // 方式1: 查询参数中的token
      if (uri.queryParameters.containsKey('token')) {
        return uri.queryParameters['token'];
      }
      
      // 方式2: 路径中的最后一段作为token (如 /s/xxx)
      final pathSegments = uri.pathSegments;
      if (pathSegments.isNotEmpty) {
        final lastSegment = pathSegments.last;
        // 验证是否像token（一般是16位或更长的字符串）
        if (lastSegment.length >= 16) {
          return lastSegment;
        }
      }
      
      return null;
    } catch (e) {
      _logger.error('提取订阅token失败', e);
      return null;
    }
  }

  /// 获取并解密加密的订阅数据（使用已知token）
  /// 
  /// [token] 用户的订阅token
  /// [preferEncrypt] 是否优先使用加密端点，默认true
  /// [enableRace] 是否启用订阅URL竞速，默认true
  /// 
  /// 返回解密后的Clash配置内容
  static Future<SubscriptionResult> getEncryptedSubscription(
    String token, {
    bool preferEncrypt = true,
    bool enableRace = true,
  }) async {
    try {
      _logger.info('开始获取加密订阅，token: ${token.substring(0, 8)}..., 竞速模式: $enableRace');

      // 1. 获取订阅配置
      final subscriptionInfo = XBoardConfig.subscriptionInfo;
      if (subscriptionInfo == null) {
        return SubscriptionResult.failure('未找到订阅配置信息');
      }

      // 2. 构建订阅URL（使用竞速或单一URL）
      String? subscriptionUrl;
      
      if (enableRace && (subscriptionInfo.urls.length > 1)) {
        _logger.info('[订阅竞速] 检测到 ${subscriptionInfo.urls.length} 个订阅源，启动竞速选择...');
        subscriptionUrl = await XBoardConfig.getFastestSubscriptionUrl(
          token,
          preferEncrypt: preferEncrypt,
        );
        _logger.info('[订阅竞速] 🏆 竞速完成，最快URL: $subscriptionUrl');
      } else {
        subscriptionUrl = subscriptionInfo.buildSubscriptionUrl(
          token, 
          forceEncrypt: preferEncrypt
        );
        _logger.debug('[订阅服务] 使用默认URL（无需竞速）: $subscriptionUrl');
      }
      
      if (subscriptionUrl == null) {
        return SubscriptionResult.failure('无法构建订阅URL');
      }

      _logger.debug('[订阅服务] 最终使用URL: $subscriptionUrl');

      // 3. 获取加密数据
      final encryptedData = await _fetchEncryptedData(subscriptionUrl);
      if (!encryptedData.success) {
        return SubscriptionResult.failure(encryptedData.error!);
      }

      _logger.debug('[订阅服务] 获取到加密数据，长度: ${encryptedData.data!.length}');

      // 4. 解密数据
      _logger.info('[订阅服务] 🔐 开始解密获取到的加密数据...');
      final decryptKey = await ConfigFileLoaderHelper.getDecryptKey();
      final decryptResult = XBoardDecryptHelper.smartDecrypt(
        encryptedData.data!,
        configuredKey: decryptKey,
        tryFallback: true, // 允许尝试备用密钥
      );
      if (!decryptResult.success) {
        _logger.error('[订阅服务] 💥 解密失败: ${decryptResult.message}');
        return SubscriptionResult.failure('解密失败: ${decryptResult.message}');
      }

      _logger.info('[订阅服务] 🎉 解密成功！使用密钥: ${decryptResult.keyUsed?.substring(0, 8)}..., 解密内容长度: ${decryptResult.content.length}');

      // 记录解密内容的基本统计信息
      final lines = decryptResult.content.split('\n');
      final nonEmptyLines = lines.where((line) => line.trim().isNotEmpty).length;
      _logger.debug('[订阅服务] 解密内容统计: 总行数 ${lines.length}, 非空行数 $nonEmptyLines');

      return SubscriptionResult.success(
        content: decryptResult.content,
        encryptionUsed: true,
        keyUsed: decryptResult.keyUsed,
        originalUrl: subscriptionUrl,
        subscriptionUserInfo: encryptedData.subscriptionUserInfo,
      );

    } catch (e) {
      _logger.error('处理过程异常', e);
      return SubscriptionResult.failure('获取加密订阅异常: $e');
    }
  }

  /// 获取加密数据（支持重试）
  /// 
  /// [url] 订阅URL
  /// 返回加密的数据内容和订阅信息
  static Future<DataResult> _fetchEncryptedData(String url) async {
    _logger.info('[数据获取] 开始获取加密数据，最大重试次数: $maxRetries');

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        _logger.debug('[数据获取] 第 $attempt/$maxRetries 次请求: $url');

        final client = HttpClient();
        client.connectionTimeout = requestTimeout;
        
        final uri = Uri.parse(url);
        final request = await client.getUrl(uri);
        
        // 设置请求头（服务端需要FlClash标识配合密钥获取Clash配置格式）
        final userAgent = await UserAgentConfig.get(UserAgentScenario.subscription);
        request.headers.set(HttpHeaders.userAgentHeader, userAgent);
        request.headers.set(HttpHeaders.acceptHeader, '*/*');
        
        final response = await request.close().timeout(requestTimeout);
        
        _logger.debug('[数据获取] HTTP状态码: ${response.statusCode}');

        if (response.statusCode == 200) {
          final responseBody = await response.transform(utf8.decoder).join();
          final subscriptionUserInfo = response.headers.value('subscription-userinfo');
          client.close();

          _logger.debug('[数据获取] ✅ 响应成功，数据长度: ${responseBody.length}');
          if (subscriptionUserInfo != null) {
            _logger.debug('[数据获取] 📊 获取到订阅信息: $subscriptionUserInfo');
          }

          // 尝试解析JSON响应
          try {
            final jsonData = jsonDecode(responseBody);
            if (jsonData is Map<String, dynamic> && jsonData.containsKey('data')) {
              _logger.debug('[数据获取] 📄 检测到JSON格式响应，提取data字段');
              final dataContent = jsonData['data'] as String;
              _logger.debug('[数据获取] 🔐 提取到加密数据长度: ${dataContent.length}');
              return DataResult.success(dataContent, subscriptionUserInfo: subscriptionUserInfo);
            }
          } catch (e) {
            _logger.debug('[数据获取] 📄 非JSON格式响应，直接返回原始内容');
            // 如果不是JSON，直接返回响应体
          }

          _logger.debug('[数据获取] 🔐 返回原始响应内容作为加密数据');
          return DataResult.success(responseBody, subscriptionUserInfo: subscriptionUserInfo);
          
        } else {
          client.close();
          
          if (attempt < maxRetries) {
            _logger.warning('[数据获取] ⚠️ 请求失败，状态码: ${response.statusCode}，${attempt * 2}秒后进行第${attempt + 1}次重试...');
            await Future.delayed(Duration(seconds: attempt * 2));
            continue;
          } else {
            _logger.error('[数据获取] 💥 请求最终失败，状态码: ${response.statusCode}，已达到最大重试次数');
            return DataResult.failure('HTTP请求失败: ${response.statusCode}');
          }
        }
        
      } on TimeoutException {
        if (attempt < maxRetries) {
          _logger.warning('[数据获取] ⏰ 请求超时，${attempt * 2}秒后进行第${attempt + 1}次重试...');
          await Future.delayed(Duration(seconds: attempt * 2));
          continue;
        } else {
          _logger.error('[数据获取] 💥 请求最终超时，已达到最大重试次数');
          return DataResult.failure('请求超时');
        }
      } catch (e) {
        if (attempt < maxRetries) {
          _logger.warning('[数据获取] ⚠️ 请求异常: $e，${attempt * 2}秒后进行第${attempt + 1}次重试...');
          await Future.delayed(Duration(seconds: attempt * 2));
          continue;
        } else {
          _logger.error('[数据获取] 💥 请求最终异常: $e，已达到最大重试次数');
          return DataResult.failure('请求异常: $e');
        }
      }
    }

    _logger.error('[数据获取] 💥 所有重试都失败了，已尝试 $maxRetries 次');
    return DataResult.failure('所有重试都失败了');
  }

  /// 回退到普通订阅获取
  /// 
  /// [token] 用户token
  /// [enableRace] 是否启用订阅URL竞速
  /// 当加密订阅失败时的备用方案
  static Future<SubscriptionResult> fallbackToNormalSubscription(
    String token, {
    bool enableRace = true,
  }) async {
    try {
      _logger.info('回退到普通订阅模式');

      final subscriptionInfo = XBoardConfig.subscriptionInfo;
      if (subscriptionInfo == null) {
        return SubscriptionResult.failure('未找到订阅配置信息');
      }

      // 尝试获取普通端点（使用竞速或单一URL）
      String? normalUrl;
      
      if (enableRace && (subscriptionInfo.urls.length > 1)) {
        _logger.info('[普通订阅竞速] 启动竞速选择普通端点...');
        normalUrl = await XBoardConfig.getFastestSubscriptionUrl(
          token,
          preferEncrypt: false,
        );
      } else {
        normalUrl = subscriptionInfo.buildSubscriptionUrl(token, forceEncrypt: false);
      }
      
      if (normalUrl == null) {
        return SubscriptionResult.failure('无法构建普通订阅URL');
      }

      final result = await _fetchEncryptedData(normalUrl);
      if (!result.success) {
        return SubscriptionResult.failure(result.error!);
      }

      return SubscriptionResult.success(
        content: result.data!,
        encryptionUsed: false,
        keyUsed: null,
        originalUrl: normalUrl,
        subscriptionUserInfo: result.subscriptionUserInfo,
      );

    } catch (e) {
      return SubscriptionResult.failure('普通订阅获取失败: $e');
    }
  }

  /// 获取订阅（智能选择加密或普通）
  /// 
  /// [token] 可选的用户token，如果不提供则从登录数据获取
  /// [preferEncrypt] 是否优先使用加密，默认true
  /// [enableRace] 是否启用订阅URL竞速，默认true
  /// 
  /// 先尝试加密订阅，失败后自动回退到普通订阅
  static Future<SubscriptionResult> getSubscriptionSmart(
    String? token, {
    bool preferEncrypt = true,
    bool enableRace = true,
  }) async {
    try {
      // 如果没有提供token，优先从登录数据获取
      if (token == null || token.isEmpty) {
        _logger.info('未提供token，从登录数据获取');
        return await getEncryptedSubscriptionFromLogin(
          preferEncrypt: preferEncrypt,
          enableRace: enableRace,
        );
      }

      // 使用提供的token
      if (preferEncrypt) {
        // 先尝试加密订阅
        final encryptedResult = await getEncryptedSubscription(
          token,
          preferEncrypt: true,
          enableRace: enableRace,
        );
        if (encryptedResult.success) {
          return encryptedResult;
        }
        
        _logger.warning('加密订阅失败，尝试普通订阅: ${encryptedResult.error}');
        
        // 回退到普通订阅
        return await fallbackToNormalSubscription(token, enableRace: enableRace);
      } else {
        // 直接使用普通订阅
        return await fallbackToNormalSubscription(token, enableRace: enableRace);
      }
    } catch (e) {
      return SubscriptionResult.failure('智能订阅获取失败: $e');
    }
  }

  // ========== 新增：并发竞速订阅获取方法 ==========

  /// 并发竞速获取加密订阅（从登录数据，推荐方法）
  /// 
  /// 使用多个订阅源并发请求，第一个成功的获胜，自动取消其他请求
  /// 
  /// [preferEncrypt] 是否优先使用加密端点，默认true
  /// [enableRace] 是否启用竞速模式，如果false则回退到标准单一请求，默认true
  /// 
  /// 返回最快成功的订阅结果
  static Future<SubscriptionResult> getRaceEncryptedSubscriptionFromLogin({
    bool preferEncrypt = true,
    bool enableRace = true,
  }) async {
    try {
      _logger.info('[竞速增强] 获取加密订阅，竞速模式: $enableRace');

      // 如果未启用竞速模式，回退到原始方法
      if (!enableRace) {
        _logger.info('[竞速增强] 竞速模式已禁用，使用标准获取方式');
        return await getEncryptedSubscriptionFromLogin(preferEncrypt: preferEncrypt);
      }

      // 使用并发竞速服务
      return await ConcurrentSubscriptionService.raceGetEncryptedSubscriptionFromLogin(
        preferEncrypt: preferEncrypt,
      );
    } catch (e) {
      _logger.error('[竞速增强] 竞速获取失败，回退到标准方式', e);
      
      // 竞速失败时回退到标准方式
      return await getEncryptedSubscriptionFromLogin(preferEncrypt: preferEncrypt);
    }
  }

  /// 并发竞速获取加密订阅（使用token）
  /// 
  /// [token] 用户的订阅token
  /// [preferEncrypt] 是否优先使用加密端点，默认true
  /// [enableRace] 是否启用竞速模式，默认true
  /// 
  /// 返回最快成功的订阅结果
  static Future<SubscriptionResult> getRaceEncryptedSubscription(
    String token, {
    bool preferEncrypt = true,
    bool enableRace = true,
  }) async {
    try {
      _logger.info('[竞速增强] 获取加密订阅，token: ${token.substring(0, 8)}..., 竞速模式: $enableRace');

      // 如果未启用竞速模式，回退到原始方法
      if (!enableRace) {
        return await getEncryptedSubscription(token, preferEncrypt: preferEncrypt);
      }

      // 使用并发竞速服务
      return await ConcurrentSubscriptionService.raceGetEncryptedSubscription(
        token, 
        preferEncrypt: preferEncrypt,
      );
    } catch (e) {
      _logger.error('[竞速增强] 竞速获取失败，回退到标准方式', e);
      
      // 竞速失败时回退到标准方式
      return await getEncryptedSubscription(token, preferEncrypt: preferEncrypt);
    }
  }
}

/// 数据获取结果
class DataResult {
  final bool success;
  final String? data;
  final String? subscriptionUserInfo;
  final String? error;

  const DataResult._({required this.success, this.data, this.subscriptionUserInfo, this.error});

  factory DataResult.success(String data, {String? subscriptionUserInfo}) => 
    DataResult._(success: true, data: data, subscriptionUserInfo: subscriptionUserInfo);
  factory DataResult.failure(String error) => DataResult._(success: false, error: error);
}

/// 订阅获取结果
class SubscriptionResult {
  final bool success;
  final String? content;
  final bool encryptionUsed;
  final String? keyUsed;
  final String? originalUrl;
  final String? subscriptionUserInfo;
  final String? error;

  const SubscriptionResult._({
    required this.success,
    this.content,
    this.encryptionUsed = false,
    this.keyUsed,
    this.originalUrl,
    this.subscriptionUserInfo,
    this.error,
  });

  factory SubscriptionResult.success({
    required String content,
    required bool encryptionUsed,
    String? keyUsed,
    String? originalUrl,
    String? subscriptionUserInfo,
  }) => SubscriptionResult._(
    success: true,
    content: content,
    encryptionUsed: encryptionUsed,
    keyUsed: keyUsed,
    originalUrl: originalUrl,
    subscriptionUserInfo: subscriptionUserInfo,
  );

  factory SubscriptionResult.failure(String error) => 
    SubscriptionResult._(success: false, error: error);

  @override
  String toString() {
    return 'SubscriptionResult(success: $success, encryption: $encryptionUsed, keyUsed: $keyUsed)';
  }
}
