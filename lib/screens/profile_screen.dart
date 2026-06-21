import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../legal/privacy_policy.dart';
import '../main.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _weightController;
  late final TextEditingController _heightController;
  late final TextEditingController _ageController;
  late final TextEditingController _conditionsController;
  late String _gender;
  late String _language;
  bool _deviceFound = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<VitaGuardState>();
    _weightController =
        TextEditingController(text: state.weight.toStringAsFixed(0));
    _heightController =
        TextEditingController(text: state.height.toStringAsFixed(0));
    _ageController = TextEditingController(text: state.age.toString());
    _conditionsController = TextEditingController(text: state.conditions);
    _gender = state.gender;
    _language = state.language;
  }

  @override
  void dispose() {
    _weightController.dispose();
    _heightController.dispose();
    _ageController.dispose();
    _conditionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VitaGuardState>();
    final compact = MediaQuery.sizeOf(context).width < 600;

    return ListView(
      padding: EdgeInsets.all(compact ? 4 : 16),
      children: [
        _ProfileHeader(state: state),
        const SizedBox(height: 14),
        _Section(
          title: 'Personal information',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ProfileTile(
                icon: Icons.monitor_weight_outlined,
                label: 'Weight',
                value: '${state.weight.toStringAsFixed(0)} kg',
              ),
              _ProfileTile(
                icon: Icons.height_outlined,
                label: 'Height',
                value: '${state.height.toStringAsFixed(0)} cm',
              ),
              _ProfileTile(
                icon: Icons.cake_outlined,
                label: 'Age',
                value: '${state.age}',
              ),
              _ProfileTile(
                icon: Icons.person_outline,
                label: 'Gender',
                value: state.gender,
              ),
              _ProfileTile(
                icon: Icons.medical_information_outlined,
                label: 'Conditions',
                value: state.conditions,
                wide: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _DeviceSection(
          deviceFound: _deviceFound,
          onFind: _findDevice,
        ),
        const SizedBox(height: 14),
        _PrivacySection(state: state),
        const SizedBox(height: 14),
        _Section(
          title: 'Settings',
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: _language,
                dropdownColor: const Color(0xFF11141B),
                decoration: const InputDecoration(labelText: 'Language'),
                items: const ['English', 'Thai']
                    .map((item) =>
                        DropdownMenuItem(value: item, child: Text(item)))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _language = value);
                  state.updateSettings(newLanguage: value);
                },
              ),
              const SizedBox(height: 10),
              _NumberField(controller: _weightController, label: 'Weight (kg)'),
              const SizedBox(height: 10),
              _NumberField(controller: _heightController, label: 'Height (cm)'),
              const SizedBox(height: 10),
              _NumberField(controller: _ageController, label: 'Age'),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _gender,
                dropdownColor: const Color(0xFF11141B),
                decoration: const InputDecoration(labelText: 'Gender'),
                items: const ['Female', 'Male', 'Other']
                    .map((item) =>
                        DropdownMenuItem(value: item, child: Text(item)))
                    .toList(),
                onChanged: (value) =>
                    setState(() => _gender = value ?? _gender),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _conditionsController,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Underlying disease / medical conditions',
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => state.updatePersonalInfo(
                    newWeight:
                        double.tryParse(_weightController.text) ?? state.weight,
                    newHeight:
                        double.tryParse(_heightController.text) ?? state.height,
                    newAge: int.tryParse(_ageController.text) ?? state.age,
                    newGender: _gender,
                    newConditions: _conditionsController.text,
                  ),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save profile'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: state.resetSetup,
                  icon: const Icon(Icons.logout),
                  label: const Text('Logout'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _findDevice() async {
    final found = await context.read<VitaGuardState>().findDeviceForSetup();
    if (!mounted) return;
    setState(() => _deviceFound = found);
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.state});

  final VitaGuardState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF11141B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF232833)),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.person_outline,
              color: Colors.black,
              size: 34,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.userName.isEmpty ? 'Profile' : state.userName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Device ID: ${state.deviceId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFFA7B0C0)),
                ),
                const SizedBox(height: 4),
                Text(
                  'Language: ${state.language}',
                  style: const TextStyle(color: Color(0xFFA7B0C0)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF11141B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF232833)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _DeviceSection extends StatelessWidget {
  const _DeviceSection({
    required this.deviceFound,
    required this.onFind,
  });

  final bool deviceFound;
  final VoidCallback onFind;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VitaGuardState>();
    final canConnect = deviceFound && !state.bleConnected && !state.scanningBle;
    final statusColor =
        state.bleConnected ? const Color(0xFF22C55E) : const Color(0xFFA7B0C0);
    final bleStatusType = state.scanningBle
        ? _StatusType.loading
        : state.bleStatus.toLowerCase().contains('failed')
            ? _StatusType.error
            : state.bleConnected || deviceFound
                ? _StatusType.success
                : _StatusType.neutral;
    final locationStatusType = state.requestingLocation
        ? _StatusType.loading
        : state.locationStatus.toLowerCase().contains('unavailable')
            ? _StatusType.error
            : state.latitude != null && state.longitude != null
                ? _StatusType.success
                : _StatusType.neutral;
    final cloudStatusType = state.cloudStatus.toLowerCase().contains('syncing')
        ? _StatusType.loading
        : state.cloudStatus.toLowerCase().contains('failed')
            ? _StatusType.error
            : state.cloudEnabled
                ? _StatusType.success
                : _StatusType.neutral;

    return _Section(
      title: 'Device',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0D12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: state.bleConnected
                        ? Colors.white
                        : const Color(0xFF343B4A),
                  ),
                ),
                child: const Icon(
                  Icons.watch_outlined,
                  color: Color(0xFFEF4444),
                  size: 30,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.bleConnected ? 'Device connected' : 'Device setup',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      state.bleStatus,
                      style: TextStyle(color: statusColor),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Battery: ${state.deviceBattery}%',
                      style: const TextStyle(color: Color(0xFFA7B0C0)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      state.locationStatus,
                      style: const TextStyle(color: Color(0xFFA7B0C0)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _StatusBanner(
            icon: Icons.bluetooth,
            text: state.bleStatus,
            type: bleStatusType,
          ),
          const SizedBox(height: 8),
          _StatusBanner(
            icon: Icons.location_on_outlined,
            text: state.locationStatus,
            type: locationStatusType,
          ),
          const SizedBox(height: 8),
          _StatusBanner(
            icon: Icons.cloud_sync_outlined,
            text: state.cloudStatus,
            type: cloudStatusType,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _DeviceDetailTile(
                  label: 'Device name', value: state.bleDeviceName),
              _DeviceDetailTile(label: 'Device ID', value: state.bleDeviceId),
              _DeviceDetailTile(
                label: 'Service UUID',
                value: state.bleServiceUuid,
              ),
              _DeviceDetailTile(
                label: 'Characteristic UUID',
                value: state.bleCharacteristicUuid,
              ),
              _DeviceDetailTile(
                label: 'Connected at',
                value: _formatDateTime(state.bleConnectedAt),
              ),
              _DeviceDetailTile(
                label: 'Last sensor update',
                value: _formatDateTime(state.lastSensorUpdateAt),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.scanningBle ? null : onFind,
                  icon: const Icon(Icons.search),
                  label: Text(
                    state.scanningBle
                        ? 'Scanning...'
                        : deviceFound
                            ? 'Device found'
                            : 'Find device',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: canConnect
                      ? () =>
                          context.read<VitaGuardState>().connectDeviceForSetup()
                      : null,
                  icon: const Icon(Icons.bluetooth_connected),
                  label: Text(state.bleConnected ? 'Connected' : 'Connect'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: state.bleConnected
                      ? () => context.read<VitaGuardState>().disconnectBle()
                      : null,
                  icon: const Icon(Icons.bluetooth_disabled),
                  label: const Text('Disconnect'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextButton.icon(
                  onPressed: state.bleConnected
                      ? null
                      : () => context.read<VitaGuardState>().disconnectBle(),
                  icon: const Icon(Icons.sensors),
                  label: const Text('Use mock BLE'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: state.requestingLocation
                  ? null
                  : () => context.read<VitaGuardState>().updateLocation(),
              icon: const Icon(Icons.location_on_outlined),
              label: Text(
                state.requestingLocation
                    ? 'Requesting location...'
                    : 'Allow location access',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacySection extends StatelessWidget {
  const _PrivacySection({required this.state});

  final VitaGuardState state;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Privacy Policy',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusBanner(
            icon: Icons.verified_user_outlined,
            text: state.privacyPolicyAcceptedAt == null
                ? 'Consent has not been recorded.'
                : 'Consent accepted at ${_formatDateTime(state.privacyPolicyAcceptedAt)}',
            type: state.privacyPolicyAcceptedAt == null
                ? _StatusType.neutral
                : _StatusType.success,
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => showPrivacyPolicyDialog(context),
              icon: const Icon(Icons.privacy_tip_outlined),
              label: const Text('Open Privacy Policy'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceDetailTile extends StatelessWidget {
  const _DeviceDetailTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return SizedBox(
      width: compact ? double.infinity : 190,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF0B0D12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF232833)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFA7B0C0),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value.isEmpty ? '-' : value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.icon,
    required this.text,
    required this.type,
  });

  final IconData icon;
  final String text;
  final _StatusType type;

  @override
  Widget build(BuildContext context) {
    final color = switch (type) {
      _StatusType.loading => const Color(0xFFF59E0B),
      _StatusType.success => const Color(0xFF22C55E),
      _StatusType.error => const Color(0xFFEF4444),
      _StatusType.neutral => const Color(0xFFA7B0C0),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          if (type == _StatusType.loading)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: color,
              ),
            )
          else
            Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

enum _StatusType { loading, success, error, neutral }

String _formatDateTime(DateTime? value) {
  if (value == null) return '-';
  final local = value.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute';
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.label,
    required this.value,
    this.wide = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final width = wide ? double.infinity : (compact ? 142.0 : 180.0);

    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0B0D12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF232833)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFFEF4444), size: 22),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFA7B0C0),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: wide ? 4 : 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
    );
  }
}
