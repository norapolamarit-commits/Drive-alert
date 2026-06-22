import 'sensor_data.dart';
import 'risk_result.dart';

class AlertRecord {
  const AlertRecord({
    required this.id,
    required this.timestamp,
    required this.sensorData,
    required this.riskResult,
    this.userResponse = '',
  });

  final String id;
  final DateTime timestamp;
  final SensorData sensorData;
  final RiskResult riskResult;
  final String userResponse;

  AlertRecord copyWith({String? userResponse}) => AlertRecord(
        id: id,
        timestamp: timestamp,
        sensorData: sensorData,
        riskResult: riskResult,
        userResponse: userResponse ?? this.userResponse,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'sensorData': sensorData.toJson(),
        'riskResult': riskResult.toJson(),
        'userResponse': userResponse,
      };

  factory AlertRecord.fromJson(Map<String, dynamic> json) => AlertRecord(
        id: json['id']?.toString() ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
            DateTime.now(),
        sensorData:
            SensorData.fromJson(json['sensorData'] as Map<String, dynamic>),
        riskResult:
            RiskResult.fromJson(json['riskResult'] as Map<String, dynamic>),
        userResponse: json['userResponse']?.toString() ?? '',
      );
}
