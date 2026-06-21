import 'dart:convert';
import 'dart:math';

class SensorData {
  SensorData({
    required this.heartRate,
    required this.spo2,
    required this.gsr,
    required this.temperature,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final int heartRate;
  final int spo2;
  final double gsr;
  final double temperature;
  final double accelX;
  final double accelY;
  final double accelZ;
  final double gyroX;
  final double gyroY;
  final double gyroZ;
  final DateTime timestamp;

  double get motionMagnitude =>
      sqrt((accelX * accelX) + (accelY * accelY) + (accelZ * accelZ));

  double get gyroMagnitude =>
      sqrt((gyroX * gyroX) + (gyroY * gyroY) + (gyroZ * gyroZ));

  int get stressLevel => gsr.clamp(0, 100).round();

  factory SensorData.fromJson(Map<String, dynamic> json) {
    return SensorData(
      heartRate: (json['heartRate'] as num?)?.round() ?? 0,
      spo2: (json['spo2'] as num?)?.round() ?? 0,
      gsr: (json['gsr'] as num?)?.toDouble() ?? 0,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0,
      accelX: (json['accelX'] as num?)?.toDouble() ?? 0,
      accelY: (json['accelY'] as num?)?.toDouble() ?? 0,
      accelZ: (json['accelZ'] as num?)?.toDouble() ?? 0,
      gyroX: (json['gyroX'] as num?)?.toDouble() ?? 0,
      gyroY: (json['gyroY'] as num?)?.toDouble() ?? 0,
      gyroZ: (json['gyroZ'] as num?)?.toDouble() ?? 0,
      timestamp: json['timestamp'] == null
          ? DateTime.now()
          : DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now(),
    );
  }

  factory SensorData.fromJsonString(String raw) {
    return SensorData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Map<String, dynamic> toJson() => {
        'heartRate': heartRate,
        'spo2': spo2,
        'gsr': gsr,
        'temperature': temperature,
        'accelX': accelX,
        'accelY': accelY,
        'accelZ': accelZ,
        'gyroX': gyroX,
        'gyroY': gyroY,
        'gyroZ': gyroZ,
        'timestamp': timestamp.toIso8601String(),
      };
}
