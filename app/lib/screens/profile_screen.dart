import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../legal/privacy_policy.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../services/cloud_service.dart';
import '../ui_text.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _weightController;
  late final TextEditingController _heightController;
  late final TextEditingController _birthDateController;
  late final TextEditingController _conditionsController;
  late final TextEditingController _emergencyNameController;
  late final TextEditingController _emergencyPhoneController;
  late String _gender;
  late String _language;
  late DateTime _birthDate;
  bool _deviceFound = false;
  bool _editingPersonalInfo = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<DozState>();
    _weightController =
        TextEditingController(text: state.weight.toStringAsFixed(0));
    _heightController =
        TextEditingController(text: state.height.toStringAsFixed(0));
    _birthDate = state.birthDate ?? _birthDateFromAge(state.age);
    _birthDateController =
        TextEditingController(text: _formatBirthDate(_birthDate));
    _conditionsController = TextEditingController(text: state.conditions);
    _emergencyNameController =
        TextEditingController(text: state.emergencyContactName);
    _emergencyPhoneController =
        TextEditingController(text: state.emergencyContactPhone);
    _gender = state.gender;
    _language = state.language;
  }

  @override
  void dispose() {
    _weightController.dispose();
    _heightController.dispose();
    _birthDateController.dispose();
    _conditionsController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DozState>();
    final compact = MediaQuery.sizeOf(context).width < 600;

    return ListView(
      padding: EdgeInsets.all(compact ? 4 : 16),
      children: [
        _ProfileHeader(state: state),
        const SizedBox(height: 14),
        _Section(
          title: uiText(context,
              english: 'Personal information', thai: 'ข้อมูลส่วนบุคคล'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!state.profileDetailsProvided)
                Text(
                  uiText(
                    context,
                    english:
                        'No optional health details saved. These details are not used by current sensor analysis. Add them only if you want them stored on this device.',
                    thai:
                        'ยังไม่มีข้อมูลสุขภาพเสริมที่บันทึก ข้อมูลเหล่านี้ไม่ถูกใช้วิเคราะห์เซนเซอร์ในรุ่นปัจจุบัน เพิ่มได้หากต้องการให้เก็บไว้ในอุปกรณ์นี้',
                  ),
                  style: const TextStyle(color: Color(0xFFA7B0C0), height: 1.4),
                )
              else
                Wrap(
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
                      label: 'Birth date',
                      value: _formatBirthDate(
                        state.birthDate ?? _birthDateFromAge(state.age),
                      ),
                    ),
                    _ProfileTile(
                      icon: Icons.person_outline,
                      label: 'Gender',
                      value: state.gender,
                    ),
                    _ProfileTile(
                      icon: Icons.contact_emergency_outlined,
                      label: 'Emergency',
                      value: state.emergencyContactPhone.isEmpty
                          ? '-'
                          : state.emergencyContactPhone,
                    ),
                    _ProfileTile(
                      icon: Icons.medical_information_outlined,
                      label: 'Conditions',
                      value: state.conditions,
                      wide: true,
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() {
                    if (!_editingPersonalInfo) {
                      _syncPersonalControllers(state);
                    }
                    _editingPersonalInfo = !_editingPersonalInfo;
                  }),
                  icon: Icon(
                      _editingPersonalInfo ? Icons.close : Icons.edit_outlined),
                  label: Text(_editingPersonalInfo
                      ? 'Cancel editing'
                      : 'Edit personal information'),
                ),
              ),
              if (_editingPersonalInfo) ...[
                const SizedBox(height: 12),
                _PersonalInfoEditor(
                  weightController: _weightController,
                  heightController: _heightController,
                  birthDateController: _birthDateController,
                  conditionsController: _conditionsController,
                  emergencyNameController: _emergencyNameController,
                  emergencyPhoneController: _emergencyPhoneController,
                  gender: _gender,
                  onGenderChanged: (value) =>
                      setState(() => _gender = value ?? _gender),
                  onBirthDateTap: _selectBirthDate,
                  onSave: () => _savePersonalInfo(state),
                ),
              ],
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
          title: uiText(context, english: 'Settings', thai: 'ตั้งค่า'),
          child: Column(
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: state.cloudEnabled,
                onChanged: null,
                title: Text(uiText(context,
                    english: 'Cloud health-data sync',
                    thai: 'ซิงก์ข้อมูลสุขภาพขึ้นคลาวด์')),
                subtitle: Text(uiText(
                  context,
                  english: 'Disabled pending privacy and security review.',
                  thai: 'ปิดไว้ระหว่างทบทวนความเป็นส่วนตัวและความปลอดภัย',
                )),
                secondary: const Icon(Icons.cloud_sync_outlined),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _language,
                dropdownColor: const Color(0xFF11141B),
                decoration: InputDecoration(
                    labelText:
                        uiText(context, english: 'Language', thai: 'ภาษา')),
                items: const ['English', 'Thai']
                    .map((item) => DropdownMenuItem(
                        value: item,
                        child: Text(item == 'English'
                            ? uiText(context,
                                english: 'English', thai: 'อังกฤษ')
                            : uiText(context, english: 'Thai', thai: 'ไทย'))))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _language = value);
                  state.updateSettings(newLanguage: value);
                },
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showExportDialog(context, state),
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('Export sensor history CSV'),
                ),
              ),
              if (AuthService.isConfigured) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmLogout(context, state),
                    icon: const Icon(Icons.logout),
                    label: const Text('Logout'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _findDevice() async {
    final found = await context.read<DozState>().findDeviceForSetup();
    if (!mounted) return;
    setState(() => _deviceFound = found);
  }

  Future<void> _confirmLogout(BuildContext context, DozState state) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'Your profile and history will remain saved on this device for this account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirm == true) await state.logout();
  }

  void _syncPersonalControllers(DozState state) {
    _weightController.text = state.weight.toStringAsFixed(0);
    _heightController.text = state.height.toStringAsFixed(0);
    _birthDate = state.birthDate ?? _birthDateFromAge(state.age);
    _birthDateController.text = _formatBirthDate(_birthDate);
    _conditionsController.text = state.conditions;
    _emergencyNameController.text = state.emergencyContactName;
    _emergencyPhoneController.text = state.emergencyContactPhone;
    _gender = state.gender;
  }

  Future<void> _savePersonalInfo(DozState state) async {
    await state.updatePersonalInfo(
      newWeight: double.tryParse(_weightController.text) ?? state.weight,
      newHeight: double.tryParse(_heightController.text) ?? state.height,
      newAge: _ageFromBirthDate(_birthDate),
      newBirthDate: _birthDate,
      newGender: _gender,
      newConditions: _conditionsController.text,
      newEmergencyContactName: _emergencyNameController.text,
      newEmergencyContactPhone: _emergencyPhoneController.text,
    );
    if (!mounted) return;
    setState(() => _editingPersonalInfo = false);
  }

  Future<void> _selectBirthDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _birthDate,
      firstDate: DateTime(now.year - 120),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.white,
              onPrimary: Colors.black,
              surface: Color(0xFF11141B),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (selected == null) return;
    setState(() {
      _birthDate = selected;
      _birthDateController.text = _formatBirthDate(selected);
    });
  }

  void _showExportDialog(BuildContext context, DozState state) {
    final csv = state.exportSensorHistoryCsv();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sensor history CSV'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(csv),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: csv));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('CSV copied')),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _PersonalInfoEditor extends StatelessWidget {
  const _PersonalInfoEditor({
    required this.weightController,
    required this.heightController,
    required this.birthDateController,
    required this.conditionsController,
    required this.emergencyNameController,
    required this.emergencyPhoneController,
    required this.gender,
    required this.onGenderChanged,
    required this.onBirthDateTap,
    required this.onSave,
  });

  final TextEditingController weightController;
  final TextEditingController heightController;
  final TextEditingController birthDateController;
  final TextEditingController conditionsController;
  final TextEditingController emergencyNameController;
  final TextEditingController emergencyPhoneController;
  final String gender;
  final ValueChanged<String?> onGenderChanged;
  final VoidCallback onBirthDateTap;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _NumberField(controller: weightController, label: 'Weight (kg)'),
        const SizedBox(height: 10),
        _NumberField(controller: heightController, label: 'Height (cm)'),
        const SizedBox(height: 10),
        TextField(
          controller: birthDateController,
          readOnly: true,
          onTap: onBirthDateTap,
          decoration: const InputDecoration(
            labelText: 'Birth date',
            suffixIcon: Icon(Icons.calendar_month_outlined),
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: gender,
          dropdownColor: const Color(0xFF11141B),
          decoration: const InputDecoration(labelText: 'Gender'),
          items: const ['Female', 'Male', 'Other']
              .map((item) => DropdownMenuItem(value: item, child: Text(item)))
              .toList(),
          onChanged: onGenderChanged,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: conditionsController,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Underlying disease / medical conditions',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: emergencyNameController,
          decoration:
              const InputDecoration(labelText: 'Emergency contact name'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: emergencyPhoneController,
          keyboardType: TextInputType.phone,
          decoration:
              const InputDecoration(labelText: 'Emergency contact phone'),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onSave,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save personal information'),
          ),
        ),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.state});

  final DozState state;

  @override
  Widget build(BuildContext context) {
    final accountId = AuthService.currentUserId;
    final authConfigured = AuthService.isConfigured;
    final isSignedIn = authConfigured && accountId != null;
    final displayName = isSignedIn
        ? (state.userName.trim().isEmpty
            ? uiText(context, english: 'Profile', thai: 'โปรไฟล์')
            : state.userName.trim())
        : authConfigured
            ? uiText(context, english: 'Account', thai: 'บัญชีผู้ใช้')
            : uiText(context,
                english: 'Local demo profile', thai: 'โปรไฟล์ทดลองในเครื่อง');
    final accountStatus = isSignedIn
        ? uiText(context, english: 'Signed in', thai: 'เข้าสู่ระบบแล้ว')
        : authConfigured
            ? uiText(context,
                english: 'Sign in to continue',
                thai: 'เข้าสู่ระบบเพื่อดำเนินการต่อ')
            : uiText(context,
                english: 'Demo account • not signed in',
                thai: 'บัญชีทดลอง • ยังไม่ได้เข้าสู่ระบบ');
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
                  displayName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  accountStatus,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFFA7B0C0)),
                ),
                const SizedBox(height: 4),
                Text(
                  uiText(context,
                      english: 'Language: ${state.language}',
                      thai:
                          'ภาษา: ${state.language == 'Thai' ? 'ไทย' : 'อังกฤษ'}'),
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
    final state = context.watch<DozState>();
    return _Section(
      title: uiText(context, english: 'My Device', thai: 'อุปกรณ์ของฉัน'),
      child: _DeviceSummaryCard(
        state: state,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _DeviceDetailScreen(
              deviceFound: deviceFound,
              onFind: onFind,
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceSummaryCard extends StatelessWidget {
  const _DeviceSummaryCard({required this.state, required this.onTap});

  final DozState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor =
        state.bleConnected ? const Color(0xFF22C55E) : const Color(0xFFA7B0C0);
    final rawTelemetry =
        state.currentSensor.rawRed != null && state.currentSensor.rawIr != null;
    final batterySummary = !state.bleConnected
        ? uiText(context,
            english: 'Battery — • Device not connected',
            thai: 'แบตเตอรี่ — • ยังไม่เชื่อมต่ออุปกรณ์')
        : rawTelemetry || state.deviceBattery == null
            ? uiText(context,
                english: 'Battery — • Not reported by firmware',
                thai: 'แบตเตอรี่ — • เฟิร์มแวร์ยังไม่ส่งค่านี้')
            : '${uiText(context, english: 'Battery', thai: 'แบตเตอรี่')}: ${state.deviceBattery}% • ${state.sensorFreshnessStatus}';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0B0D12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF232833)),
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFF11141B),
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
                      uiText(
                        context,
                        english: state.bleConnected
                            ? 'Device connected'
                            : 'Device setup',
                        thai: state.bleConnected
                            ? 'เชื่อมต่ออุปกรณ์แล้ว'
                            : 'ตั้งค่าอุปกรณ์',
                      ),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(localizedBleStatus(context, state.bleStatus),
                        style: TextStyle(color: statusColor)),
                    const SizedBox(height: 4),
                    Text(
                      batterySummary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFFA7B0C0)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Color(0xFFA7B0C0)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceDetailScreen extends StatelessWidget {
  const _DeviceDetailScreen({
    required this.deviceFound,
    required this.onFind,
  });

  final bool deviceFound;
  final VoidCallback onFind;

  @override
  Widget build(BuildContext context) {
    String copy(String en, String th) => uiText(context, english: en, thai: th);
    final state = context.watch<DozState>();
    final canConnect = deviceFound && !state.bleConnected && !state.scanningBle;
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
    final sensorStatusType =
        state.sensorStatus.toLowerCase().contains('invalid') ||
                state.sensorFreshnessStatus.toLowerCase().contains('stale')
            ? _StatusType.error
            : state.lastSensorUpdateAt != null
                ? _StatusType.success
                : _StatusType.neutral;
    final sensorStatusText = localizedSensorStatus(context, state.sensorStatus);
    final freshnessStatusText =
        localizedBleStatus(context, state.sensorFreshnessStatus);
    final combinedSensorStatus = sensorStatusText == freshnessStatusText
        ? sensorStatusText
        : '$sensorStatusText • $freshnessStatusText';

    return Scaffold(
      backgroundColor: const Color(0xFF050608),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    copy('My Device', 'อุปกรณ์ของฉัน'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _StatusBanner(
              icon: Icons.bluetooth,
              text: localizedBleStatus(context, state.bleStatus),
              type: bleStatusType,
            ),
            const SizedBox(height: 8),
            _StatusBanner(
              icon: Icons.location_on_outlined,
              text: localizedLocationStatus(context, state.locationStatus),
              type: locationStatusType,
            ),
            const SizedBox(height: 8),
            _StatusBanner(
              icon: Icons.cloud_sync_outlined,
              text: localizedCloudStatus(context, state.cloudStatus),
              type: cloudStatusType,
            ),
            const SizedBox(height: 8),
            _StatusBanner(
              icon: Icons.sensors,
              text: combinedSensorStatus,
              type: sensorStatusType,
            ),
            const SizedBox(height: 8),
            _StatusBanner(
              icon: Icons.notifications_active_outlined,
              text: state.notificationStatus,
              type: _StatusType.neutral,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () =>
                    context.read<DozState>().requestNotifications(),
                icon: const Icon(Icons.notifications_active_outlined),
                label: Text(copy('Enable notifications', 'เปิดการแจ้งเตือน')),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _DeviceDetailTile(
                    label: copy('Device name', 'ชื่ออุปกรณ์'),
                    value: state.bleDeviceName),
                _DeviceDetailTile(
                    label: copy('Device ID', 'รหัสอุปกรณ์'),
                    value: state.bleDeviceId),
                _DeviceDetailTile(
                  label: copy('Service UUID', 'Service UUID'),
                  value: state.bleServiceUuid,
                ),
                _DeviceDetailTile(
                  label: copy('Characteristic UUID', 'Characteristic UUID'),
                  value: state.bleCharacteristicUuid,
                ),
                _DeviceDetailTile(
                  label: copy('Connected at', 'เวลาเชื่อมต่อ'),
                  value: _formatDateTime(state.bleConnectedAt),
                ),
                _DeviceDetailTile(
                  label: copy('Last sensor update', 'อัปเดตเซนเซอร์ล่าสุด'),
                  value: _formatDateTime(state.lastSensorUpdateAt),
                ),
                _DeviceDetailTile(
                  label: copy('Firmware', 'เฟิร์มแวร์'),
                  value: copy('Not reported', 'ยังไม่มีข้อมูล'),
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
                          ? copy('Scanning...', 'กำลังค้นหา…')
                          : deviceFound
                              ? copy('Device found', 'พบอุปกรณ์แล้ว')
                              : copy('Find device', 'ค้นหาอุปกรณ์'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: canConnect
                        ? () => context.read<DozState>().connectDeviceForSetup()
                        : null,
                    icon: const Icon(Icons.bluetooth_connected),
                    label: Text(state.bleConnected
                        ? copy('Connected', 'เชื่อมต่อแล้ว')
                        : copy('Connect', 'เชื่อมต่อ')),
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
                        ? () => context.read<DozState>().disconnectBle()
                        : null,
                    icon: const Icon(Icons.bluetooth_disabled),
                    label: Text(copy('Disconnect', 'ยกเลิกการเชื่อมต่อ')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextButton.icon(
                    onPressed: state.bleConnected
                        ? null
                        : () => context.read<DozState>().disconnectBle(),
                    icon: const Icon(Icons.sensors),
                    label: Text(copy('Use demo data', 'ใช้ข้อมูลสาธิต')),
                  ),
                ),
              ],
            ),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => context.read<DozState>().forgetDevice(),
                icon: const Icon(Icons.delete_outline),
                label: Text(copy('Forget device', 'ลืมอุปกรณ์นี้')),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: state.requestingLocation
                    ? null
                    : () => context.read<DozState>().updateLocation(),
                icon: const Icon(Icons.location_on_outlined),
                label: Text(
                  state.requestingLocation
                      ? copy('Requesting location...', 'กำลังขอตำแหน่ง…')
                      : copy(
                          'Allow location access', 'อนุญาตการเข้าถึงตำแหน่ง'),
                ),
              ),
            ),
            if (state.latitude != null && state.longitude != null) ...[
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: state.requestingLocation
                      ? null
                      : () => context.read<DozState>().clearLocation(),
                  icon: const Icon(Icons.location_off_outlined),
                  label: Text(
                      copy('Clear saved location', 'ลบตำแหน่งที่บันทึกไว้')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PrivacySection extends StatelessWidget {
  const _PrivacySection({required this.state});

  final DozState state;

  @override
  Widget build(BuildContext context) {
    String copy(String en, String th) => uiText(context, english: en, thai: th);
    return _Section(
      title: copy('Privacy Policy', 'ความเป็นส่วนตัว'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusBanner(
            icon: Icons.verified_user_outlined,
            text: state.privacyPolicyAcceptedAt == null
                ? copy('Consent has not been recorded.',
                    'ยังไม่มีบันทึกความยินยอม')
                : copy(
                    'Consent accepted at ${_formatDateTime(state.privacyPolicyAcceptedAt)} • Version ${state.privacyPolicyVersion}',
                    'ยินยอมเมื่อ ${_formatDateTime(state.privacyPolicyAcceptedAt)} • ฉบับ ${state.privacyPolicyVersion}',
                  ),
            type: state.privacyPolicyAcceptedAt == null
                ? _StatusType.neutral
                : _StatusType.success,
          ),
          const SizedBox(height: 8),
          Text(
            copy(
              'Cloud sync is disabled. Remote chatbot processing is optional and asks separately before sending a request.',
              'ปิดการซิงก์ข้อมูลขึ้นคลาวด์ไว้ การประมวลผล chatbot ระยะไกลเป็นตัวเลือก และจะแจ้งขอความยินยอมแยกก่อนส่งคำขอ',
            ),
            style: const TextStyle(color: Color(0xFFA7B0C0)),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => showPrivacyPolicyDialog(
                context,
                allowAccept: false,
              ),
              icon: const Icon(Icons.privacy_tip_outlined),
              label: Text(
                  copy('Open Privacy Policy', 'อ่านประกาศความเป็นส่วนตัว')),
            ),
          ),
          if (AuthService.isConfigured) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _requestAccountDeletion(context),
                icon: const Icon(Icons.person_remove_outlined),
                label: Text(copy('Delete account and associated data',
                    'ลบบัญชีและข้อมูลที่เกี่ยวข้อง')),
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFEF4444),
                side: const BorderSide(color: Color(0xFFEF4444)),
              ),
              onPressed: () => _confirmDeleteAllData(context, state),
              icon: const Icon(Icons.delete_forever_outlined),
              label: Text(copy('Delete local alerts & clear sensor buffer',
                  'ลบประวัติแจ้งเตือนและล้างข้อมูลเซนเซอร์')),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _requestAccountDeletion(BuildContext context) async {
    String copy(String en, String th) => uiText(context, english: en, thai: th);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
            copy('Delete account permanently?', 'ลบบัญชีอย่างถาวรหรือไม่?')),
        content: Text(copy(
          'This permanently deletes your signed-in account and associated server-side sensor/alert records. After the server confirms deletion, this app also removes this account’s local profile and alert history. This cannot be undone.',
          'การดำเนินการนี้จะลบบัญชีที่เข้าสู่ระบบและบันทึกเซนเซอร์/การแจ้งเตือนบนเซิร์ฟเวอร์อย่างถาวร เมื่อเซิร์ฟเวอร์ยืนยันการลบแล้ว แอปจะลบโปรไฟล์และประวัติการแจ้งเตือนในเครื่องของบัญชีนี้ด้วย และไม่สามารถย้อนกลับได้',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(copy('Cancel', 'ยกเลิก')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(copy('Delete account', 'ลบบัญชี')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final result = await context.read<DozState>().deleteAccount();
    if (!context.mounted) return;
    final message = switch (result) {
      AccountDeletionResult.deleted => copy(
          'Account and associated data deleted.',
          'ลบบัญชีและข้อมูลที่เกี่ยวข้องแล้ว',
        ),
      AccountDeletionResult.notConfigured => copy(
          'The deletion request could not start because the API or required server-side deletion services are not configured or available.',
          'เริ่มคำขอลบไม่ได้ เพราะยังไม่ได้ตั้งค่า API หรือบริการฝั่งเซิร์ฟเวอร์ที่จำเป็น',
        ),
      AccountDeletionResult.failed => copy(
          'Deletion was not confirmed. Some server data may already have been removed. Local account data was retained; check with support before retrying.',
          'ยังยืนยันการลบไม่สำเร็จ ข้อมูลบนเซิร์ฟเวอร์บางส่วนอาจถูกลบไปแล้ว ข้อมูลในเครื่องยังคงอยู่ โปรดตรวจสอบกับผู้ดูแลก่อนลองซ้ำ',
        ),
      AccountDeletionResult.deletedLocalCleanupFailed => copy(
          'The server deleted the account, but some local data could not be cleared. Restart the app and verify local profile/history cleanup.',
          'เซิร์ฟเวอร์ลบบัญชีแล้ว แต่ล้างข้อมูลในเครื่องบางส่วนไม่สำเร็จ ให้ปิดเปิดแอปใหม่และตรวจสอบโปรไฟล์/ประวัติในเครื่อง',
        ),
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmDeleteAllData(
      BuildContext context, DozState state) async {
    String copy(String en, String th) => uiText(context, english: en, thai: th);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(copy('Delete local alerts and clear sensor buffer?',
            'ลบประวัติแจ้งเตือนในเครื่องและล้างข้อมูลเซนเซอร์หรือไม่?')),
        content: Text(copy(
          'This removes locally stored alert history and clears up to 240 sensor readings held in app memory. Your profile, account, and data held by external services are not affected.',
          'การดำเนินการนี้จะลบประวัติการแจ้งเตือนที่เก็บในเครื่องและล้างข้อมูลเซนเซอร์ในหน่วยความจำของแอปไม่เกิน 240 รายการ โดยไม่กระทบโปรไฟล์ บัญชี หรือข้อมูลที่บริการภายนอกจัดเก็บ',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(copy('Cancel', 'ยกเลิก')),
          ),
          TextButton(
            style:
                TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(copy('Delete', 'ลบ')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await state.deleteAllData();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(copy(
          'Local alerts deleted; sensor buffer cleared',
          'ลบประวัติแจ้งเตือนในเครื่องและล้างข้อมูลเซนเซอร์แล้ว',
        )),
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

DateTime _birthDateFromAge(int age) {
  final now = DateTime.now();
  return DateTime(now.year - age, now.month, now.day);
}

int _ageFromBirthDate(DateTime birthDate) {
  final now = DateTime.now();
  var age = now.year - birthDate.year;
  final hasNotHadBirthdayThisYear = now.month < birthDate.month ||
      (now.month == birthDate.month && now.day < birthDate.day);
  if (hasNotHadBirthdayThisYear) age -= 1;
  return age.clamp(0, 120);
}

String _formatBirthDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
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
