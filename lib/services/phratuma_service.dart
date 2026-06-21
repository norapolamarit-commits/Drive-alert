import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/risk_result.dart';
import '../models/sensor_data.dart';

class PhratumaService {
  PhratumaService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<String> ask({
    required String endpoint,
    required String model,
    required String userMessage,
    required SensorData sensorData,
    required RiskResult riskResult,
    required bool enabled,
    required bool useMockResponse,
    String userProfile = '',
    String alertHistory = '',
  }) async {
    if (!enabled || useMockResponse) {
      return fallbackAnswer(
          userMessage, sensorData, riskResult, userProfile, alertHistory);
    }

    try {
      final response = await _client
          .post(
            Uri.parse(endpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'model': model,
              'prompt': buildPrompt(
                userMessage: userMessage,
                sensorData: sensorData,
                riskResult: riskResult,
                userProfile: userProfile,
                alertHistory: alertHistory,
              ),
              'stream': false,
            }),
          )
          .timeout(const Duration(seconds: 18));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return fallbackAnswer(
            userMessage, sensorData, riskResult, userProfile, alertHistory);
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final answer = (body['answer'] ?? body['response'])?.toString().trim();
      return answer == null || answer.isEmpty
          ? fallbackAnswer(
              userMessage, sensorData, riskResult, userProfile, alertHistory)
          : answer;
    } catch (_) {
      return fallbackAnswer(
          userMessage, sensorData, riskResult, userProfile, alertHistory);
    }
  }

  String buildPrompt({
    required String userMessage,
    required SensorData sensorData,
    required RiskResult riskResult,
    String userProfile = '',
    String alertHistory = '',
  }) {
    return '''
You are Vita gaurd AI Health Monitoring Assistant.
Explain Risk Detection and Early Warning results in simple language.
Provide safety recommendations and user guidance.

Current sensor data:
Heart Rate: ${sensorData.heartRate} BPM
SpO2: ${sensorData.spo2} %
GSR: ${sensorData.gsr.toStringAsFixed(1)}
Temperature: ${sensorData.temperature.toStringAsFixed(1)}
Motion Magnitude: ${sensorData.motionMagnitude.toStringAsFixed(2)}
Gyro Magnitude: ${sensorData.gyroMagnitude.toStringAsFixed(2)}

Current risk analysis:
Risk Class: ${riskResult.riskClass}
Alert Level: ${riskResult.alertLevel}
Detected Signs: ${riskResult.detectedSigns.join(', ')}
Recommendation: ${riskResult.recommendation}

User profile:
$userProfile

Recent alert history:
$alertHistory

User question:
$userMessage

Use simple language.
Give clear and safe advice.
If alert level is Emergency, recommend stopping activity and contacting emergency support if symptoms continue.
''';
  }

  String fallbackAnswer(
    String userMessage,
    SensorData sensorData,
    RiskResult riskResult,
    String userProfile,
    String alertHistory,
  ) {
    final values =
        'Heart Rate ${sensorData.heartRate} BPM, SpO2 ${sensorData.spo2}%, GSR ${sensorData.gsr.toStringAsFixed(1)}, Temperature ${sensorData.temperature.toStringAsFixed(1)}°C';
    if (userMessage.toLowerCase().contains('history') ||
        userMessage.toLowerCase().contains('trend')) {
      return 'Recent history: ${alertHistory.isEmpty ? 'No repeated alerts yet.' : alertHistory}. Current Risk Detection result is ${riskResult.riskClass} at ${riskResult.alertLevel}. ${riskResult.recommendation}';
    }
    if (riskResult.alertLevel == 'Emergency') {
      return 'Vita gaurd detected ${riskResult.riskClass} at Emergency level. Contributing values: $values. Stop activity, stay in a safe place, and contact emergency support if the condition continues. Profile considered: $userProfile';
    }
    if (riskResult.alertLevel == 'Warning') {
      return 'Vita gaurd detected ${riskResult.riskClass} at Warning level because ${riskResult.detectedSigns.join(', ')}. Contributing values: $values. Recommended action: ${riskResult.recommendation}';
    }
    return 'Current Health Monitoring status is ${riskResult.riskClass} at ${riskResult.alertLevel}. Contributing values: $values. Recommended action: ${riskResult.recommendation}';
  }
}
