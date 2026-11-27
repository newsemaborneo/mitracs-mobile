import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiClient {
  static const String defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://mitracsai.my.id/api/v1',
  );
  static String baseUrl = defaultBaseUrl;
  final Dio dio = Dio();
  final FlutterSecureStorage storage = const FlutterSecureStorage();

  ApiClient() {
    dio.options.baseUrl = baseUrl;
    dio.options.connectTimeout = const Duration(seconds: 15);
    dio.options.receiveTimeout = const Duration(seconds: 15);

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final customUrl = await storage.read(key: 'custom_base_url');
          if (customUrl != null && customUrl.isNotEmpty) {
            options.baseUrl = customUrl;
          }
          final token = await storage.read(key: 'jwt_token');
          final activeBusinessId = await storage.read(key: 'active_business_id');

          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          if (activeBusinessId != null) {
            options.headers['X-Business-Id'] = activeBusinessId;
          }

          return handler.next(options);
        },
        onError: (DioException error, handler) {
          return handler.next(error);
        },
      ),
    );
  }
}
