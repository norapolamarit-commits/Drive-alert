import 'dart:convert';
import 'dart:math';

class SensorData {
  SensorData({
    required this.heartRate,
    required this.spo2,
    required this.gsr,
    required this.temperature,
    this.ecgRate = 0,
    this.ecgRrInterval = 0,
    this.ecgHrv = 0,
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
  final int ecgRate;
  final double ecgRrInterval;
  final double ecgHrv;
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
      heartRate: _num(json, 'heart_rate', 'heartRate').round(),
      spo2: _num(json, 'spo2').round(),
      gsr: _num(json, 'gsr'),
      temperature: _num(json, 'temperature'),
      ecgRate: _num(json, 'ecg_rate', 'ecgRate').round(),
      ecgRrInterval: _num(json, 'ecg_rr_interval', 'ecgRrInterval'),
      ecgHrv: _num(json, 'ecg_hrv', 'ecgHrv'),
      accelX: _num(json, 'accel_x', 'accelX'),
      accelY: _num(json, 'accel_y', 'accelY'),
      accelZ: _num(json, 'accel_z', 'accelZ'),
      gyroX: _num(json, 'gyro_x', 'gyroX'),
      gyroY: _num(json, 'gyro_y', 'gyroY'),
      gyroZ: _num(json, 'gyro_z', 'gyroZ'),
      timestamp: json['timestamp'] == null
          ? DateTime.now()
          : DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now(),
    );
  }

  factory SensorData.fromJsonString(String raw) {
    return SensorData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Map<String, dynamic> toJson() => {
        'heart_rate': heartRate,
        'spo2': spo2,
        'ecg_rate': ecgRate,
        'ecg_rr_interval': ecgRrInterval,
        'ecg_hrv': ecgHrv,
        'gsr': gsr,
        'temperature': temperature,
        'accel_x': accelX,
        'accel_y': accelY,
        'accel_z': accelZ,
        'gyro_x': gyroX,
        'gyro_y': gyroY,
        'gyro_z': gyroZ,
        'motion_magnitude': motionMagnitude,
        'gyro_magnitude': gyroMagnitude,
        'heartRate': heartRate,
        'ecgRate': ecgRate,
        'ecgRrInterval': ecgRrInterval,
        'ecgHrv': ecgHrv,
        'accelX': accelX,
        'accelY': accelY,
        'accelZ': accelZ,
        'gyroX': gyroX,
        'gyroY': gyroY,
        'gyroZ': gyroZ,
        'timestamp': timestamp.toIso8601String(),
      };
}

double _num(Map<String, dynamic> json, String key, [String? fallbackKey]) {
  final value = json[key] ?? (fallbackKey == null ? null : json[fallbackKey]);
  return value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
}
