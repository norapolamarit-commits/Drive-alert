import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../widgets/risk_explanation_card.dart';
import '../widgets/sensor_card.dart';
import '../widgets/status_card.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final state = context.watch<DozState>();
    final sensor = state.currentSensor;
    final risk = state.currentRisk;
    final activeAlerts =
        state.alerts.where((item) => item.userResponse.isEmpty).length;

    return ListView(
      padding: EdgeInsets.all(compact ? 8 : 16),
      children: [
        _WatchConnectionCard(state: state),
        SizedBox(height: compact ? 8 : 12),
        StatusCard(
          status: risk.riskClass,
          alertLevel: risk.alertLevel,
          recommendation: risk.recommendation,
        ),
        SizedBox(height: compact ? 8 : 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: compact ? 1.42 : 1.15,
          crossAxisSpacing: compact ? 8 : 10,
          mainAxisSpacing: compact ? 8 : 10,
          children: [
            SensorCard(
                title: 'Active Alerts',
                value: '$activeAlerts',
                unit: '',
                icon: Icons.warning_amber),
            SensorCard(
                title: 'Latest Alert Level',
                value: risk.alertLevel,
                unit: '',
                icon: Icons.shield_outlined),
            SensorCard(
                title: 'Detected Risk',
                value: risk.riskClass,
                unit: '',
                icon: Icons.radar_outlined),
            SensorCard(
                title: 'Device Battery',
                value: '${state.deviceBattery}',
                unit: '%',
                icon: Icons.battery_5_bar),
          ],
        ),
        SizedBox(height: compact ? 8 : 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: compact ? 1.42 : 1.15,
          crossAxisSpacing: compact ? 8 : 10,
          mainAxisSpacing: compact ? 8 : 10,
          children: [
            SensorCard(
                title: 'Heart Rate',
                value: '${sensor.heartRate}',
                unit: 'BPM',
                icon: Icons.favorite_outline),
            SensorCard(
                title: 'SpO2',
                value: '${sensor.spo2}',
                unit: '%',
                icon: Icons.air_outlined),
            SensorCard(
                title: 'Stress Level',
                value: '${sensor.stressLevel}',
                unit: '',
                icon: Icons.bolt_outlined),
            SensorCard(
                title: 'GSR',
                value: sensor.gsr.toStringAsFixed(0),
                unit: '',
                icon: Icons.sensors_outlined),
            SensorCard(
                title: 'Temperature',
                value: sensor.temperature.toStringAsFixed(1),
                unit: '°C',
                icon: Icons.thermostat_outlined),
            SensorCard(
                title: 'BLE Status',
                value: state.bleConnected ? 'BLE' : 'Mock BLE',
                unit: '',
                icon: Icons.bluetooth),
          ],
        ),
        SizedBox(height: compact ? 8 : 12),
        RiskExplanationCard(risk: risk),
        SizedBox(height: compact ? 8 : 12),
        _PersonalInfo(state: state),
      ],
    );
  }
}

class _WatchConnectionCard extends StatelessWidget {
  const _WatchConnectionCard({required this.state});

  final DozState state;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final connectedText = state.bleConnected ? 'Connected' : 'Demo stream';
    final signalText = state.bleConnected ? 'BLE live' : 'Mock BLE';

    return Container(
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: BoxDecoration(
        color: const Color(0xFF11141B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF232833)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF151922), Color(0xFF0B0D12)],
        ),
      ),
      child: Row(
        children: [
          const _WatchIllustration(),
          SizedBox(width: compact ? 14 : 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'doz',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$connectedText • $signalText',
                  style: const TextStyle(color: Color(0xFFA7B0C0)),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _WatchChip(
                      icon: Icons.bluetooth,
                      label: state.bleConnected ? 'BLE' : 'Mock',
                    ),
                    _WatchChip(
                      icon: Icons.battery_5_bar,
                      label: '${state.deviceBattery}%',
                    ),
                    _WatchChip(
                      icon: Icons.sync,
                      label: state.cloudEnabled ? 'Cloud' : 'Local',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WatchIllustration extends StatelessWidget {
  const _WatchIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      height: 108,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 0,
            child: Container(
              width: 30,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF232833),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            child: Container(
              width: 30,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF232833),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Container(
            width: 62,
            height: 74,
            decoration: BoxDecoration(
              color: const Color(0xFF050608),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(
              Icons.watch_outlined,
              color: Color(0xFFEF4444),
              size: 30,
            ),
          ),
        ],
      ),
    );
  }
}

class _WatchChip extends StatelessWidget {
  const _WatchChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF050608),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF343B4A)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFFEF4444)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _PersonalInfo extends StatelessWidget {
  const _PersonalInfo({required this.state});

  final DozState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF11141B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF232833)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Personal information',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text('Weight: ${state.weight.toStringAsFixed(0)} kg'),
          Text('Height: ${state.height.toStringAsFixed(0)} cm'),
          Text('Age: ${state.age}'),
          Text('Gender: ${state.gender}'),
          Text('Underlying disease / medical conditions: ${state.conditions}'),
        ],
      ),
    );
  }
}
