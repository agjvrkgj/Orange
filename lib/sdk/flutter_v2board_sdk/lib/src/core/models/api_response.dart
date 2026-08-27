/// API响应基础模型 - 兼容XBoard格式
class ApiResponse<T> {
  final bool success;
  final String? message;
  final T? data;
  final int? code;
  final dynamic error;

  ApiResponse({
    required this.success,
    this.message,
    this.data,
    this.code,
    this.error,
  });

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic)? fromJsonT,
  ) {
    // Support explicit success/status envelopes and V2Board's standard
    // `{ "data": ... }` response. HTTP failures are converted to exceptions
    // by HttpService before this factory is reached.
    bool isSuccess = false;
    if (json.containsKey('success')) {
      isSuccess = json['success'] ?? false;
    } else if (json.containsKey('status')) {
      isSuccess = json['status'] == 'success';
    } else {
      isSuccess = !json.containsKey('error');
    }

    return ApiResponse<T>(
      success: isSuccess,
      message: json['message'],
      code: json['code'],
      error: json['error'],
      data: json['data'] != null && fromJsonT != null
          ? fromJsonT(json['data'])
          : json['data'],
    );
  }
}
