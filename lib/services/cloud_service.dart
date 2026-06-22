import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/alert_record.dart';
import '../models/risk_result.dart';
import '../models/sensor_data.dart';

class CloudService {
  CloudService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<bool> uploadSensor({
    required String baseUrl,
    required SensorData sensorData,
    required RiskResult riskResult,
    required Map<String, dynamic> userProfile,
    required int battery,
    required String bleStatus,
    required String sensorStatus,
  }) async {
    if (baseUrl.trim().isEmpty) return false;
    return _post(
      baseUrl: baseUrl,
      path: '/sensor',
      body: {
        'timestamp': sensorData.timestamp.toIso8601String(),
        'sensorData': sensorData.toJson(),
        'riskResult': riskResult.toJson(),
        'userProfile': userProfile,
        'battery': battery,
        'bleStatus': bleStatus,
        'sensorStatus': sensorStatus,
      },
    );
  }

  Future<bool> uploadAlert({
    required String baseUrl,
    required AlertRecord alert,
    required Map<String, dynamic> userProfile,
  }) async {
    if (baseUrl.trim().isEmpty) return false;
    return _post(
      baseUrl: baseUrl,
      path: '/alert',
      body: {
        'alert': alert.toJson(),
        'userProfile': userProfile,
      },
    );
  }

  Future<bool> _post({
    required String baseUrl,
    required String path,
    required Map<String, dynamic> body,
  }) async {
    try {
      final normalized = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final response = await _client
          .post(
            Uri.parse('$normalized$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 4));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}
