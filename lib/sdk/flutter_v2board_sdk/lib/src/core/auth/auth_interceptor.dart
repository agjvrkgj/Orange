import 'package:dio/dio.dart';
import 'token_manager.dart';
import '../logging/sdk_logger.dart';

/// 认证拦截器（简化版）
/// 自动为HTTP请求添加token，不处理自动刷新和重试
class AuthInterceptor extends Interceptor {
  final TokenManager _tokenManager;
  final Set<String> _publicEndpoints;

  AuthInterceptor({
    required TokenManager tokenManager,
    Set<String>? publicEndpoints,
  })  : _tokenManager = tokenManager,
        _publicEndpoints = publicEndpoints ?? _defaultPublicEndpoints;

  /// 默认的公开端点（无需token的接口）
  static const Set<String> _defaultPublicEndpoints = {
    '/api/v1/passport/auth/login',
    '/api/v1/passport/auth/register',
    '/api/v1/passport/comm/sendEmailVerify',
    '/api/v1/passport/auth/forget',
    '/api/v1/guest/comm/config',
  };

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    try {
      // 检查是否为公开端点
      if (_isPublicEndpoint(options.path)) {
        handler.next(options);
        return;
      }

      // V2Board expects auth_data as the raw Authorization header. Do not
      // add a Bearer prefix: AuthService::decryptAuthData receives this value
      // directly and decodes it as a JWT.
      final token = await _tokenManager.getToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = token;
      }

      handler.next(options);
    } catch (e, stackTrace) {
      SdkLogger.e('[AuthInterceptor] Error in onRequest', e, stackTrace);
      handler.next(options); // 继续请求，让服务器返回401
    }
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401) {
      SdkLogger.w(
          '[AuthInterceptor] 401 Unauthorized: ${err.requestOptions.path}');
      // TODO: 这里可以添加 Token 过期通知逻辑
    }
    handler.next(err);
  }

  /// 检查是否为公开端点
  bool _isPublicEndpoint(String path) {
    // 精确匹配
    if (_publicEndpoints.contains(path)) {
      return true;
    }

    // 路径匹配（考虑查询参数）
    for (final endpoint in _publicEndpoints) {
      if (path.startsWith(endpoint)) {
        // 确保是完整路径匹配，避免误匹配
        final remaining = path.substring(endpoint.length);
        if (remaining.isEmpty ||
            remaining.startsWith('?') ||
            remaining.startsWith('/')) {
          return true;
        }
      }
    }

    return false;
  }

  /// 添加公开端点
  void addPublicEndpoint(String endpoint) {
    _publicEndpoints.add(endpoint);
  }

  /// 移除公开端点
  void removePublicEndpoint(String endpoint) {
    _publicEndpoints.remove(endpoint);
  }

  /// 获取所有公开端点
  Set<String> get publicEndpoints => Set.unmodifiable(_publicEndpoints);
}
