import 'dart:math';

import '../models/sensor_data.dart';

class MockDataService {
  final Random _random = Random();
  int _tick = 0;

  static const scenarios = [
    'Normal',
    'Drowsiness Risk',
    'Fatigue Risk',
    'Seizure-like Risk',
    'High Stress Alert',
    'Immobilization Alert',
  ];

  SensorData nextAuto() {
    // หมุนเวียนผ่านทุกสถานการณ์ที่เหลือ คั่นด้วยช่วง Normal
    final profile = _tick % 40;
    if (profile >= 6 && profile <= 9) return next('Drowsiness Risk');
    if (profile >= 13 && profile <= 16) return next('Fatigue Risk');
    if (profile >= 22 && profile <= 24) return next('High Stress Alert');
    if (profile >= 30 && profile <= 32) return next('Seizure-like Risk');
    if (profile == 38) return next('Immobilization Alert');
    return next('Normal');
  }

  SensorData next(String scenario) {
    _tick++;
    final wave = sin(_tick / 3);
    final jitter = (_random.nextDouble() - 0.5) * 0.08;

    switch (scenario) {
      case 'Drowsiness Risk':
        return _base(
          heartRate: max(48, 78 - _tick % 18),
          spo2: 96,
          gsr: max(18, 45 - _tick % 20).toDouble(),
          motion: 0.18 + jitter,
          gyro: 0.05,
        );
      case 'Fatigue Risk':
        return _base(
          heartRate: 112 + (_random.nextInt(8)),
          spo2: 95,
          gsr: 74 + _random.nextDouble() * 12,
          motion: 0.45 + jitter,
          gyro: 0.35,
        );
      case 'Seizure-like Risk':
        return _base(
          heartRate: 118,
          spo2: 94,
          gsr: 78,
          motion: 1.3 + wave.abs(),
          gyro: 2.4 + wave.abs(),
        );
      case 'High Stress Alert':
        return _base(
          heartRate: 112,
          spo2: 96,
          gsr: 88,
          motion: 0.6,
          gyro: 0.25,
        );
      case 'Immobilization Alert':
        return _base(
          heartRate: 76,
          spo2: 97,
          gsr: 44,
          motion: 0.08,
          gyro: 0.02,
        );
      case 'Normal':
      default:
        return _base(
          heartRate: 74 + _random.nextInt(12),
          spo2: 96 + _random.nextInt(3),
          gsr: 42 + _random.nextDouble() * 12,
          motion: 0.85 + jitter,
          gyro: 0.18 + jitter.abs(),
        );
    }
  }

  SensorData _base({
    required int heartRate,
    required int spo2,
    required double gsr,
    required double motion,
    required double gyro,
  }) {
    return SensorData(
      heartRate: heartRate,
      spo2: spo2,
      gsr: gsr,
      temperature: 36.3 + _random.nextDouble() * 0.8,
      accelX: motion / 3,
      accelY: motion / 4,
      accelZ: max(0.02, motion),
      gyroX: gyro / 2,
      gyroY: gyro / 3,
      gyroZ: gyro / 4,
    );
  }
}
