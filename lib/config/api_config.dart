import 'package:flutter/foundation.dart';

class ApiConfig {
  static String? _customBaseUrl;

  static String get baseUrl {
    if (_customBaseUrl != null && _customBaseUrl!.trim().isNotEmpty) {
      return _customBaseUrl!.trim().replaceAll(RegExp(r'/$'), '');
    }
    if (kIsWeb) {
      return 'http://localhost:5239';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5239';
    }
    return 'http://localhost:5239';
  }

  static void setBaseUrl(String? url) {
    _customBaseUrl = url;
  }

  static String get meEndpoint => '$baseUrl/api/me';
  static String get safeZoneEndpoint => '$baseUrl/api/me/safe/zone';
  static String get dangerZoneEndpoint => '$baseUrl/api/me/danger/zone';
}
