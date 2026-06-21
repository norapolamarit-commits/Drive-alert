import 'risk_result.dart';
import 'sensor_data.dart';

class SensorRiskSample {
  const SensorRiskSample({
    required this.sensorData,
    required this.riskResult,
  });

  final SensorData sensorData;
  final RiskResult riskResult;
}
