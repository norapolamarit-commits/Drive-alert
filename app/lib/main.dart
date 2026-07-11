import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/alert_record.dart';
import 'models/chat_message.dart';
import 'models/risk_result.dart';
import 'models/sensor_data.dart';
import 'models/sensor_risk_sample.dart';
import 'screens/alert_history_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/graph_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/setup_screen.dart';
import 'services/alert_storage_service.dart';
import 'services/ble_service.dart';
import 'services/cloud_service.dart';
import 'services/location_service.dart';
import 'services/mock_data_service.dart';
import 'services/notification_service.dart';
import 'services/phratuma_service.dart';
import 'services/risk_analyzer.dart';

void main() {
  runApp(const DozApp());
}

class DozApp extends StatelessWidget {
  const DozApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DozState()..initialize(),
      child: MaterialApp(
        title: 'doz',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFEF4444),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF050608),
          useMaterial3: true,
          cardTheme: CardThemeData(
            color: const Color(0xFF11141B),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFF11141B),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF343B4A)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.white),
            ),
          ),
        ),
        home: const DozGate(),
      ),
    );
  }
}

class DozGate extends StatelessWidget {
  const DozGate({super.key});

  @override
  Widget build(BuildContext context) {
    final setupDone = context.watch<DozState>().setupDone;
    return setupDone ? const DozShell() : const SetupScreen();
  }
}

class DozShell extends StatefulWidget {
  const DozShell({super.key});

  @override
  State<DozShell> createState() => _DozShellState();
}

class _DozShellState extends State<DozShell> {
  int _index = 0;

  static const _screens = [
    DashboardScreen(),
    GraphScreen(),
    AlertHistoryScreen(),
    ProfileScreen(),
  ];

  static const _tabLabels = [
    'Current Health Status',
    'Health Data & History',
    'Risk Alert Log',
    'Profile',
  ];

  static const _bottomLabels = [
    'Status',
    'Data',
    'Alerts',
    'Profile',
  ];

  static const _tabIcons = [
    Icons.watch_outlined,
    Icons.monitor_heart_outlined,
    Icons.notifications_active_outlined,
    Icons.person_outline,
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 820;
        final content = _MainContent(
          selectedIndex: _index,
          labels: _tabLabels,
          screens: _screens,
          showTopTabs: wide,
          onSelected: (index) => setState(() => _index = index),
        );

        if (wide) {
          return Scaffold(
            body: SafeArea(child: content),
          );
        }

        return Scaffold(
          body: SafeArea(
            child: Stack(
              children: [
                content,
                Positioned(
                  top: 4,
                  right: 4,
                  child: _SettingsGearButton(
                    onPressed: () =>
                        setState(() => _index = _screens.length - 1),
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: _BottomPageTabs(
            selectedIndex: _index,
            labels: _bottomLabels,
            icons: _tabIcons,
            onSelected: (index) => setState(() => _index = index),
          ),
        );
      },
    );
  }
}

class _SettingsGearButton extends StatelessWidget {
  const _SettingsGearButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF11141B),
      borderRadius: BorderRadius.circular(8),
      child: IconButton(
        tooltip: 'Profile / Settings',
        onPressed: onPressed,
        icon: const Icon(Icons.settings, color: Colors.white),
      ),
    );
  }
}

class _MainContent extends StatelessWidget {
  const _MainContent({
    required this.selectedIndex,
    required this.labels,
    required this.screens,
    required this.showTopTabs,
    required this.onSelected,
  });

  final int selectedIndex;
  final List<String> labels;
  final List<Widget> screens;
  final bool showTopTabs;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Padding(
      padding: compact
          ? const EdgeInsets.fromLTRB(16, 18, 16, 14)
          : const EdgeInsets.fromLTRB(36, 28, 36, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showTopTabs) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(
                  labels.length,
                  (index) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _StreamlitTab(
                      label: labels[index],
                      selected: selectedIndex == index,
                      onTap: () => onSelected(index),
                    ),
                  ),
                ),
              ),
            ),
            Divider(height: compact ? 18 : 28, color: const Color(0xFF11141B)),
          ] else ...[
            SizedBox(height: compact ? 48 : 0),
          ],
          Expanded(child: screens[selectedIndex]),
        ],
      ),
    );
  }
}

class _BottomPageTabs extends StatelessWidget {
  const _BottomPageTabs({
    required this.selectedIndex,
    required this.labels,
    required this.icons,
    required this.onSelected,
  });

  final int selectedIndex;
  final List<String> labels;
  final List<IconData> icons;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelected,
        backgroundColor: const Color(0xFF050608),
        indicatorColor: Colors.white,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: List.generate(
          labels.length,
          (index) => NavigationDestination(
            icon: Icon(icons[index], color: const Color(0xFFA7B0C0)),
            selectedIcon: Icon(icons[index], color: Colors.black),
            label: labels[index],
          ),
        ),
      ),
    );
  }
}

class _StreamlitTab extends StatelessWidget {
  const _StreamlitTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 11 : 14,
          vertical: compact ? 9 : 12,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF11141B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? Colors.white : const Color(0xFF232833),
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 14 : null,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class DozState extends ChangeNotifier {
  final MockDataService _mockDataService = MockDataService();
  final RiskAnalyzer _riskAnalyzer = RiskAnalyzer();
  final AlertStorageService _alertStorage = AlertStorageService();
  final PhratumaService _phratumaService = PhratumaService();
  final BleService _bleService = BleService();
  final CloudService _cloudService = CloudService();
  final LocationService _locationService = LocationService();
  final NotificationService _notificationService = NotificationService();

  SensorData currentSensor = SensorData(
    heartRate: 78,
    spo2: 97,
    gsr: 45,
    temperature: 36.7,
    accelX: 0.1,
    accelY: 0.2,
    accelZ: 1.0,
    gyroX: 0.02,
    gyroY: 0.01,
    gyroZ: 0.03,
  );

  RiskResult currentRisk = const RiskResult(
    riskClass: 'Normal',
    alertLevel: 'Safe',
    detectedSigns: [
      'Current sensor values are within the expected monitoring range.'
    ],
    recommendation: 'Continue normal activity and keep monitoring.',
  );

  final List<SensorData> sensorHistory = [];
  final List<SensorRiskSample> sensorRiskHistory = [];
  final List<AlertRecord> alerts = [];
  final List<ChatMessage> chatMessages = [
    ChatMessage(
      text:
          'Hello, I am doz assistant. I can explain early warnings, sensor values, actions, and history.',
      isUser: false,
    ),
  ];

  bool setupDone = false;
  bool llmEnabled = true;
  bool mockChatbotResponse = false;
  bool cloudEnabled = false;
  String language = 'English';
  String userId = '';
  String deviceId = '';
  String phratumaEndpoint = 'https://your-render-or-mock-api.example.com/chat';
  String cloudBaseUrl =
      const String.fromEnvironment('VITAGAURD_CLOUD_BASE_URL');
  String modelName = 'nectec/Pathumma-llm-text-1.0.0:featherless-ai';
  bool bleConnected = false;
  bool scanningBle = false;
  String bleStatus = 'Mock BLE stream';
  String bleDeviceName = 'No device selected';
  String bleDeviceId = '-';
  String bleServiceUuid = '-';
  String bleCharacteristicUuid = '-';
  DateTime? bleConnectedAt;
  DateTime? lastSensorUpdateAt;
  String sensorStatus = 'No sensor data yet';
  String cloudStatus = 'Cloud sync disabled';
  String aiAdvice = ''; // คำแนะนำจาก LLM (โหมดให้คำแนะนำอย่างเดียว)
  String aiAdviceCause = ''; // สาเหตุที่ระบบตรวจพบ (จาก /advice)
  String aiAdviceDisclaimer = ''; // ข้อความปฏิเสธความรับผิด (จาก /advice)
  String _lastAdviceFor = ''; // กันเรียก LLM ซ้ำสถานะเดิม

  // ── Response-timeout escalation: Warning ที่ไม่ตอบรับใน 30 วิ → ยกระดับ Emergency ──
  // ผูกกับ "episode" ของสถานะ (currentRisk.alertLevel) ไม่ใช่ AlertRecord ใดตัวหนึ่ง
  // เพื่อไม่ให้ dedup-window (20s) รีเซ็ตตัวจับเวลาก่อนครบ 30s
  static const Duration _warningResponseTimeout = Duration(seconds: 30);
  Timer? _warningTimer;
  bool _warningEpisodeAcknowledged = false;
  bool _disposed = false;
  String locationStatus = 'Location not requested';
  String notificationStatus = 'Notification not requested';
  bool requestingLocation = false;
  double? latitude;
  double? longitude;
  int deviceBattery = 96;
  DateTime? privacyPolicyAcceptedAt;
  String privacyPolicyVersion = '1.1';
  final List<String> consentScopes = const [
    'health_data',
    'location',
    'ble_device',
    'cloud_sync',
  ];

  String userName = '';
  String emergencyContactName = '';
  String emergencyContactPhone = '';
  double weight = 60;
  double height = 165;
  int age = 20;
  DateTime? birthDate;
  String gender = 'Female';
  String conditions = 'None';

  Timer? _timer;
  StreamSubscription<SensorData>? _bleSubscription;
  bool _sensorCloudSyncInFlight = false;
  bool _alertCloudSyncInFlight = false;

  Future<void> initialize() async {
    await _loadSettings();
    if (bleServiceUuid == '-') {
      bleServiceUuid = _bleService.configuredServiceUuid.isEmpty
          ? 'Auto-detect'
          : _bleService.configuredServiceUuid;
    }
    if (bleCharacteristicUuid == '-') {
      bleCharacteristicUuid = _bleService.configuredCharacteristicUuid.isEmpty
          ? 'Auto notify/indicate characteristic'
          : _bleService.configuredCharacteristicUuid;
    }
    alerts
      ..clear()
      ..addAll(await _alertStorage.loadAlerts());
    await _initializeNotifications();
    _startMockLoop();
    _bleSubscription = _bleService.sensorStream.listen(updateSensorData);
    notifyListeners();
  }

  void _startMockLoop() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!bleConnected) updateSensorData(_mockDataService.nextAuto());
    });
  }

  Future<void> completeSetup({
    required String newName,
    DateTime? newPrivacyPolicyAcceptedAt,
    required double newWeight,
    required double newHeight,
    required int newAge,
    DateTime? newBirthDate,
    required String newGender,
    required String newConditions,
  }) async {
    userName = newName.trim();
    weight = newWeight;
    height = newHeight;
    age = newAge;
    birthDate = newBirthDate ?? birthDate;
    gender = newGender;
    conditions = newConditions.trim().isEmpty ? 'None' : newConditions.trim();
    privacyPolicyAcceptedAt =
        newPrivacyPolicyAcceptedAt ?? privacyPolicyAcceptedAt;
    setupDone = true;
    bleStatus = bleConnected ? bleStatus : 'Mock BLE stream connected';
    await _saveSettings();
    notifyListeners();
  }

  Future<void> updatePersonalInfo({
    required double newWeight,
    required double newHeight,
    required int newAge,
    DateTime? newBirthDate,
    required String newGender,
    required String newConditions,
    String? newEmergencyContactName,
    String? newEmergencyContactPhone,
  }) {
    emergencyContactName =
        newEmergencyContactName?.trim() ?? emergencyContactName;
    emergencyContactPhone =
        newEmergencyContactPhone?.trim() ?? emergencyContactPhone;
    return completeSetup(
      newName: userName,
      newWeight: newWeight,
      newHeight: newHeight,
      newAge: newAge,
      newBirthDate: newBirthDate,
      newGender: newGender,
      newConditions: newConditions,
    );
  }

  Future<void> resetSetup() async {
    setupDone = false;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> updateSensorData(SensorData data) async {
    currentSensor = data;
    lastSensorUpdateAt = DateTime.now();
    sensorStatus = _sensorStatusFor(data);
    deviceBattery = (96 - sensorHistory.length ~/ 4).clamp(18, 96).toInt();
    currentRisk = _riskAnalyzer.analyze(data, sensorHistory);
    // ติดตาม response-timeout ตาม "สถานะปัจจุบัน" ทุก tick — ไม่ผูกกับ dedup ด้านล่าง
    // (ถ้าผูกกับ alert ที่ถูก dedup กันไว้ ตัวจับเวลาจะถูกรีเซ็ตก่อนครบ 30s เสมอ)
    _trackWarningEscalation(currentRisk);
    sensorHistory.add(data);
    if (sensorHistory.length > 240) sensorHistory.removeAt(0);
    sensorRiskHistory
        .add(SensorRiskSample(sensorData: data, riskResult: currentRisk));
    if (sensorRiskHistory.length > 240) sensorRiskHistory.removeAt(0);

    if (currentRisk.shouldStoreAlert) {
      final recentDuplicate = alerts.isNotEmpty &&
          alerts.first.riskResult.riskClass == currentRisk.riskClass &&
          DateTime.now().difference(alerts.first.timestamp).inSeconds < 20;
      if (!recentDuplicate) {
        final alert = AlertRecord(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          timestamp: DateTime.now(),
          sensorData: data,
          riskResult: currentRisk,
        );
        alerts.insert(0, alert);
        await _alertStorage.saveAlerts(alerts);
        _showAlertNotification(alert);
        _syncAlertToCloud(alert);
      }
    }
    _syncSensorToCloud(data, currentRisk);
    _refreshAdvice(data, currentRisk);
    notifyListeners();
  }

  /// ติดตาม "episode" ของ Warning เพื่อยกระดับเป็น Emergency ถ้าไม่ตอบรับภายในเวลาที่กำหนด
  /// (response-timeout escalation — ผู้ใช้อาจหมดสติ/หลับในจริง จึงไม่ตอบรับ)
  ///
  /// ตั้งใจแยกจาก dedup-window ของการบันทึก alert (20s) โดยสิ้นเชิง: ผูกกับสถานะ
  /// ปัจจุบัน (currentRisk.alertLevel) ไม่ใช่ AlertRecord ตัวใดตัวหนึ่ง — เรียกทุก tick
  /// จึงเริ่มจับเวลาแค่ครั้งเดียวตอน episode เริ่ม (ไม่ถูกรีเซ็ตทุกครั้งที่มี Warning ซ้ำ
  /// ก่อนครบ 30 วิ ซึ่งเป็นบั๊กเดิมที่ทำให้ escalation ไม่มีทางทำงานกับ Warning ต่อเนื่องจริง)
  void _trackWarningEscalation(RiskResult risk) {
    if (risk.alertLevel != 'Warning') {
      // episode จบแล้ว (กลับปกติ หรือแย่ลงเป็น Emergency เองแล้ว) → เลิกติดตาม
      _warningTimer?.cancel();
      _warningTimer = null;
      return;
    }
    if (_warningTimer != null) return; // episode นี้กำลังถูกติดตามอยู่แล้ว — อย่ารีเซ็ต
    _warningEpisodeAcknowledged = false;
    _warningTimer = Timer(_warningResponseTimeout, _checkWarningEscalation);
  }

  void _checkWarningEscalation() {
    _warningTimer = null;
    if (_disposed) return;
    // ตรวจกับสถานะสดตอนนี้ ไม่ใช่ตอนเริ่มจับเวลา — กันเคสที่กลับเป็นปกติไปแล้ว
    if (currentRisk.alertLevel != 'Warning' || _warningEpisodeAcknowledged) {
      return;
    }
    _escalateUnacknowledgedWarning();
  }

  Future<void> _escalateUnacknowledgedWarning() async {
    final escalatedRisk = RiskResult(
      riskClass: currentRisk.riskClass,
      alertLevel: 'Emergency',
      detectedSigns: [
        ...currentRisk.detectedSigns,
        'ไม่มีการตอบรับภายใน ${_warningResponseTimeout.inSeconds} วินาที',
      ],
      recommendation:
          'ไม่มีการตอบรับการแจ้งเตือน — หยุดกิจกรรมทันที ตรวจสอบความปลอดภัย '
          'หากไม่ตอบสนอง โทร 1669',
    );
    final escalated = AlertRecord(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      sensorData: currentSensor,
      riskResult: escalatedRisk,
    );
    alerts.insert(0, escalated);
    await _alertStorage.saveAlerts(alerts);
    if (_disposed) return;
    // อัปเดตสถานะปัจจุบันด้วย — ไม่งั้นหน้า Dashboard ยังโชว์ Warning เดิม
    // ทั้งที่ประวัติแจ้งเตือนมี Emergency แล้ว (เห็นแค่ถ้าเข้าไปดู Alert History)
    currentRisk = escalatedRisk;
    _showAlertNotification(escalated);
    _syncAlertToCloud(escalated);
    notifyListeners();
  }

  /// ดึงคำแนะนำจาก LLM เมื่อสถานะเปลี่ยน (เฉพาะตอนไม่ปกติ) — โหมดให้คำแนะนำอย่างเดียว
  Future<void> _refreshAdvice(SensorData data, RiskResult risk) async {
    // สถานะปกติ → เคลียร์คำแนะนำ AI (ใช้ข้อความ rule-based เดิม)
    if (risk.alertLevel == 'Safe') {
      if (aiAdvice.isNotEmpty) {
        aiAdvice = '';
        aiAdviceCause = '';
        aiAdviceDisclaimer = '';
        _lastAdviceFor = '';
        notifyListeners();
      }
      return;
    }
    // เรียกเฉพาะเมื่อสถานะเปลี่ยน (กันยิง LLM ซ้ำๆ) และเปิด cloud อยู่
    if (risk.riskClass == _lastAdviceFor || cloudBaseUrl.trim().isEmpty) return;
    _lastAdviceFor = risk.riskClass;

    final sensor =
        'HR ${data.heartRate} bpm, SpO2 ${data.spo2}%, HRV ${data.ecgHrv.toStringAsFixed(0)} ms, '
        'GSR ${data.gsr.toStringAsFixed(0)}, Temp ${data.temperature.toStringAsFixed(1)}°C';
    final result = await _cloudService.fetchAdvice(
      baseUrl: cloudBaseUrl,
      status: risk.riskClass,
      alertLevel: risk.alertLevel,
      sensor: sensor,
    );
    if (result != null && _lastAdviceFor == risk.riskClass) {
      aiAdvice = result.advice;
      aiAdviceCause = result.cause;
      aiAdviceDisclaimer = result.disclaimer;
      notifyListeners();
    }
  }

  Future<void> respondToLatestAlert(String response) async {
    if (alerts.isEmpty) return;
    await respondToAlert(alerts.first.id, response);
  }

  Future<void> respondToAlert(String id, String response) async {
    final index = alerts.indexWhere((item) => item.id == id);
    if (index == -1) return;
    alerts[index] = alerts[index].copyWith(userResponse: response);
    await _alertStorage.saveAlerts(alerts);
    // ตอบรับ alert ล่าสุด (ที่แสดงอยู่) ระหว่าง episode ที่กำลังติดตาม → เลื่อนกำหนด
    // ยกระดับออกไปอีก 30 วิ (ตัวจับเวลาใหม่จะถูกตั้งในรอบ updateSensorData ถัดไป)
    if (alerts.isNotEmpty && id == alerts.first.id) {
      _warningEpisodeAcknowledged = true;
      _warningTimer?.cancel();
      _warningTimer = null;
    }
    notifyListeners();
  }

  /// PDPA: ลบข้อมูลสุขภาพที่เก็บไว้ทั้งหมด (ประวัติแจ้งเตือน + log เซนเซอร์)
  /// ไม่แตะโปรไฟล์/การตั้งค่า — แยกจาก resetSetup (logout) โดยตั้งใจ
  Future<void> deleteAllData() async {
    _warningTimer?.cancel();
    _warningTimer = null;
    _warningEpisodeAcknowledged = false;
    alerts.clear();
    sensorHistory.clear();
    sensorRiskHistory.clear();
    aiAdvice = '';
    aiAdviceCause = '';
    aiAdviceDisclaimer = '';
    _lastAdviceFor = '';
    await _alertStorage.clearAlerts();
    notifyListeners();
  }

  Future<void> askChatbot(String message) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;
    chatMessages.add(ChatMessage(text: trimmed, isUser: true));
    notifyListeners();

    final answer = await _phratumaService.ask(
      endpoint: phratumaEndpoint,
      model: modelName,
      userMessage: trimmed,
      sensorData: currentSensor,
      riskResult: currentRisk,
      enabled: llmEnabled,
      useMockResponse: mockChatbotResponse,
      userProfile:
          'Name $userName, age $age, weight ${weight.toStringAsFixed(0)} kg, height ${height.toStringAsFixed(0)} cm, gender $gender, conditions: $conditions',
      alertHistory:
          alerts.take(6).map((item) => item.riskResult.riskClass).join(', '),
    );
    chatMessages.add(ChatMessage(text: answer, isUser: false));
    notifyListeners();
  }

  Future<void> updateSettings({
    String? endpoint,
    String? model,
    String? cloudUrl,
    String? newLanguage,
    bool? enableLlm,
    bool? useMockChat,
    bool? enableCloud,
  }) async {
    phratumaEndpoint = endpoint ?? phratumaEndpoint;
    modelName = model ?? modelName;
    cloudBaseUrl = cloudUrl ?? cloudBaseUrl;
    language = newLanguage ?? language;
    llmEnabled = enableLlm ?? llmEnabled;
    mockChatbotResponse = useMockChat ?? mockChatbotResponse;
    cloudEnabled = enableCloud ?? cloudEnabled;
    cloudStatus = cloudEnabled ? 'Cloud sync ready' : 'Cloud sync disabled';
    await _saveSettings();
    notifyListeners();
  }

  Map<String, dynamic> get userProfile => {
        'userId': userId,
        'deviceId': deviceId,
        'name': userName,
        'age': age,
        'birthDate': birthDate?.toIso8601String(),
        'weight': weight,
        'height': height,
        'gender': gender,
        'conditions': conditions,
        'emergencyContactName': emergencyContactName,
        'emergencyContactPhone': emergencyContactPhone,
        'latitude': latitude,
        'longitude': longitude,
        'privacyPolicyAcceptedAt': privacyPolicyAcceptedAt?.toIso8601String(),
        'privacyPolicyVersion': privacyPolicyVersion,
        'consentScopes': consentScopes,
      };

  String get sensorFreshnessStatus {
    final last = lastSensorUpdateAt;
    if (last == null) return 'No sensor data yet';
    final age = DateTime.now().difference(last);
    if (age.inSeconds <= 8) return 'Receiving data';
    if (age.inSeconds <= 30) return 'Sensor data delayed';
    return 'Sensor data stale';
  }

  String exportSensorHistoryCsv() {
    final buffer = StringBuffer();
    buffer.writeln(
      'timestamp,user_id,device_id,heart_rate,spo2,ecg_rate,ecg_rr_interval,ecg_hrv,gsr,temperature,accel_x,accel_y,accel_z,gyro_x,gyro_y,gyro_z,motion_magnitude,gyro_magnitude,risk_class,alert_level',
    );
    for (final sample in sensorRiskHistory) {
      final sensor = sample.sensorData;
      final risk = sample.riskResult;
      buffer.writeln([
        sensor.timestamp.toIso8601String(),
        userId,
        deviceId,
        sensor.heartRate,
        sensor.spo2,
        sensor.ecgRate,
        sensor.ecgRrInterval,
        sensor.ecgHrv,
        sensor.gsr,
        sensor.temperature,
        sensor.accelX,
        sensor.accelY,
        sensor.accelZ,
        sensor.gyroX,
        sensor.gyroY,
        sensor.gyroZ,
        sensor.motionMagnitude,
        sensor.gyroMagnitude,
        risk.riskClass,
        risk.alertLevel,
      ].map(_csvCell).join(','));
    }
    return buffer.toString();
  }

  String _sensorStatusFor(SensorData data) {
    final invalid = data.heartRate < 0 ||
        data.spo2 < 0 ||
        data.spo2 > 100 ||
        data.temperature < 20 ||
        data.temperature > 45;
    if (invalid) return 'Invalid sensor value received';
    return bleConnected ? 'Receiving BLE sensor data' : 'Receiving mock data';
  }

  Future<void> _syncSensorToCloud(
      SensorData data, RiskResult riskResult) async {
    if (!cloudEnabled ||
        cloudBaseUrl.trim().isEmpty ||
        _sensorCloudSyncInFlight) {
      return;
    }
    _sensorCloudSyncInFlight = true;
    cloudStatus = 'Syncing sensor to cloud...';
    notifyListeners();
    final ok = await _cloudService.uploadSensor(
      baseUrl: cloudBaseUrl,
      sensorData: data,
      riskResult: riskResult,
      userProfile: userProfile,
      battery: deviceBattery,
      bleStatus: bleStatus,
      sensorStatus: sensorStatus,
    );
    cloudStatus = ok
        ? 'Cloud synced ${DateTime.now().toLocal().toIso8601String().substring(11, 19)}'
        : 'Cloud sync failed';
    _sensorCloudSyncInFlight = false;
    notifyListeners();
  }

  Future<void> _syncAlertToCloud(AlertRecord alert) async {
    if (!cloudEnabled ||
        cloudBaseUrl.trim().isEmpty ||
        _alertCloudSyncInFlight) {
      return;
    }
    _alertCloudSyncInFlight = true;
    cloudStatus = 'Syncing alert to cloud...';
    notifyListeners();
    final ok = await _cloudService.uploadAlert(
      baseUrl: cloudBaseUrl,
      alert: alert,
      userProfile: userProfile,
    );
    cloudStatus = ok ? 'Alert synced to cloud' : 'Cloud alert sync failed';
    _alertCloudSyncInFlight = false;
    notifyListeners();
  }

  Future<void> _initializeNotifications() async {
    try {
      final ok = await _notificationService.initialize();
      notificationStatus =
          ok ? 'Notifications ready' : 'Notification permission denied';
    } catch (error) {
      notificationStatus = 'Notification unavailable: $error';
    }
  }

  Future<void> requestNotifications() async {
    try {
      final ok = await _notificationService.requestPermission();
      notificationStatus =
          ok ? 'Notifications ready' : 'Notification permission denied';
    } catch (error) {
      notificationStatus = 'Notification unavailable: $error';
    }
    await _saveSettings();
    notifyListeners();
  }

  Future<void> _showAlertNotification(AlertRecord alert) async {
    await _notificationService.showRiskAlert(
      riskResult: alert.riskResult,
      heartRate: alert.sensorData.heartRate,
      spo2: alert.sensorData.spo2,
    );
    notificationStatus = _notificationService.permissionGranted
        ? 'Last notification sent'
        : 'Notification permission denied';
  }

  Future<bool> findDeviceForSetup() async {
    scanningBle = true;
    bleStatus = 'Scanning ESP32...';
    notifyListeners();
    try {
      final results = await _bleService.scanForEsp32();
      final found = results.isNotEmpty;
      if (found) {
        bleDeviceName = _bleService.lastFoundDeviceName;
        bleDeviceId = _bleService.lastFoundDeviceId;
        bleStatus = 'Device found: $bleDeviceName';
      } else {
        bleStatus = 'ESP32 not found. Mock stream available.';
      }
      return found;
    } catch (error) {
      bleStatus = 'BLE scan failed: $error';
      return false;
    } finally {
      scanningBle = false;
      notifyListeners();
    }
  }

  Future<bool> connectDeviceForSetup() async {
    scanningBle = true;
    bleStatus = 'Connecting ESP32...';
    notifyListeners();
    try {
      await _bleService.connectLastFound();
      bleConnected = true;
      bleConnectedAt = DateTime.now();
      bleDeviceName = _bleService.connectedDeviceName;
      bleDeviceId = _bleService.connectedDeviceId;
      bleServiceUuid = _bleService.connectedServiceUuid;
      bleCharacteristicUuid = _bleService.connectedCharacteristicUuid;
      bleStatus = 'Connected to $bleDeviceName';
      await _saveSettings();
      return true;
    } catch (error) {
      bleStatus = 'BLE connection failed: $error';
      return false;
    } finally {
      scanningBle = false;
      notifyListeners();
    }
  }

  Future<void> scanAndConnectBle() async {
    scanningBle = true;
    bleStatus = 'Scanning ESP32...';
    notifyListeners();

    try {
      final results = await _bleService.scanForEsp32();
      if (results.isEmpty) {
        bleStatus = 'ESP32 not found. Using mock BLE stream.';
      } else {
        await _bleService.connect(results.first.device);
        bleConnected = true;
        bleConnectedAt = DateTime.now();
        bleDeviceName = _bleService.connectedDeviceName;
        bleDeviceId = _bleService.connectedDeviceId;
        bleServiceUuid = _bleService.connectedServiceUuid;
        bleCharacteristicUuid = _bleService.connectedCharacteristicUuid;
        bleStatus = 'Connected to $bleDeviceName';
        await _saveSettings();
      }
    } catch (error) {
      bleStatus = 'BLE connection failed. Using mock BLE stream.';
    } finally {
      scanningBle = false;
      notifyListeners();
    }
  }

  Future<void> disconnectBle() async {
    await _bleService.disconnect();
    bleConnected = false;
    bleConnectedAt = null;
    bleStatus = 'Mock BLE stream connected';
    await _saveSettings();
    notifyListeners();
  }

  Future<void> forgetDevice() async {
    await _bleService.disconnect();
    bleConnected = false;
    bleConnectedAt = null;
    bleDeviceName = 'No device selected';
    bleDeviceId = '-';
    bleServiceUuid = _bleService.configuredServiceUuid.isEmpty
        ? 'Auto-detect'
        : _bleService.configuredServiceUuid;
    bleCharacteristicUuid = _bleService.configuredCharacteristicUuid.isEmpty
        ? 'Auto notify/indicate characteristic'
        : _bleService.configuredCharacteristicUuid;
    bleStatus = 'Device forgotten. Mock BLE stream connected';
    await _saveSettings();
    notifyListeners();
  }

  Future<bool> updateLocation() async {
    requestingLocation = true;
    locationStatus = 'Requesting location...';
    notifyListeners();

    try {
      final position = await _locationService.getCurrentPosition();
      latitude = position.latitude;
      longitude = position.longitude;
      locationStatus =
          'Location ready: ${latitude!.toStringAsFixed(5)}, ${longitude!.toStringAsFixed(5)}';
      await _saveSettings();
      return true;
    } catch (error) {
      locationStatus = 'Location unavailable: $error';
      return false;
    } finally {
      requestingLocation = false;
      notifyListeners();
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    const configuredCloudBaseUrl =
        String.fromEnvironment('VITAGAURD_CLOUD_BASE_URL');
    setupDone = prefs.getBool('setupDone') ?? setupDone;
    userId = prefs.getString('userId') ?? userId;
    if (userId.isEmpty) {
      userId = 'user-${DateTime.now().microsecondsSinceEpoch}';
      await prefs.setString('userId', userId);
    }
    deviceId = prefs.getString('deviceId') ?? deviceId;
    if (deviceId.isEmpty) {
      deviceId = 'device-${DateTime.now().microsecondsSinceEpoch}';
      await prefs.setString('deviceId', deviceId);
    }
    phratumaEndpoint = prefs.getString('phratumaEndpoint') ?? phratumaEndpoint;
    cloudBaseUrl = configuredCloudBaseUrl.isNotEmpty
        ? configuredCloudBaseUrl
        : (prefs.getString('cloudBaseUrl') ?? cloudBaseUrl);
    // ถ้าตั้ง base URL ผ่าน --dart-define ให้ chatbot ใช้ /chat ของ server เดียวกัน
    // (กันกรณีค้าง placeholder example.com แล้ว chatbot ตอบ fallback เดิมทุกครั้ง)
    if (configuredCloudBaseUrl.isNotEmpty) {
      final base = configuredCloudBaseUrl.replaceAll(RegExp(r'/+$'), '');
      phratumaEndpoint = '$base/chat';
    }
    modelName = prefs.getString('modelName') ?? modelName;
    language = prefs.getString('language') ?? language;
    llmEnabled = prefs.getBool('llmEnabled') ?? llmEnabled;
    mockChatbotResponse =
        prefs.getBool('mockChatbotResponse') ?? mockChatbotResponse;
    cloudEnabled = configuredCloudBaseUrl.isNotEmpty ||
        (prefs.getBool('cloudEnabled') ?? cloudEnabled);
    cloudStatus = cloudEnabled ? 'Cloud sync ready' : 'Cloud sync disabled';
    bleDeviceName = prefs.getString('bleDeviceName') ?? bleDeviceName;
    bleDeviceId = prefs.getString('bleDeviceId') ?? bleDeviceId;
    bleServiceUuid = prefs.getString('bleServiceUuid') ?? bleServiceUuid;
    bleCharacteristicUuid =
        prefs.getString('bleCharacteristicUuid') ?? bleCharacteristicUuid;
    final connectedAtRaw = prefs.getString('bleConnectedAt');
    bleConnectedAt =
        connectedAtRaw == null ? null : DateTime.tryParse(connectedAtRaw);
    final lastSensorAtRaw = prefs.getString('lastSensorUpdateAt');
    lastSensorUpdateAt =
        lastSensorAtRaw == null ? null : DateTime.tryParse(lastSensorAtRaw);
    sensorStatus = prefs.getString('sensorStatus') ?? sensorStatus;
    userName = prefs.getString('userName') ?? userName;
    emergencyContactName =
        prefs.getString('emergencyContactName') ?? emergencyContactName;
    emergencyContactPhone =
        prefs.getString('emergencyContactPhone') ?? emergencyContactPhone;
    final acceptedAtRaw = prefs.getString('privacyPolicyAcceptedAt');
    privacyPolicyAcceptedAt =
        acceptedAtRaw == null ? null : DateTime.tryParse(acceptedAtRaw);
    weight = prefs.getDouble('weight') ?? weight;
    height = prefs.getDouble('height') ?? height;
    age = prefs.getInt('age') ?? age;
    final birthDateRaw = prefs.getString('birthDate');
    birthDate = birthDateRaw == null ? null : DateTime.tryParse(birthDateRaw);
    gender = prefs.getString('gender') ?? gender;
    conditions = prefs.getString('conditions') ?? conditions;
    latitude = prefs.getDouble('latitude');
    longitude = prefs.getDouble('longitude');
    if (latitude != null && longitude != null) {
      locationStatus =
          'Location ready: ${latitude!.toStringAsFixed(5)}, ${longitude!.toStringAsFixed(5)}';
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('setupDone', setupDone);
    await prefs.setString('userId', userId);
    await prefs.setString('deviceId', deviceId);
    await prefs.setString('phratumaEndpoint', phratumaEndpoint);
    await prefs.setString('cloudBaseUrl', cloudBaseUrl);
    await prefs.setString('modelName', modelName);
    await prefs.setString('language', language);
    await prefs.setBool('llmEnabled', llmEnabled);
    await prefs.setBool('mockChatbotResponse', mockChatbotResponse);
    await prefs.setBool('cloudEnabled', cloudEnabled);
    await prefs.setString('bleDeviceName', bleDeviceName);
    await prefs.setString('bleDeviceId', bleDeviceId);
    await prefs.setString('bleServiceUuid', bleServiceUuid);
    await prefs.setString('bleCharacteristicUuid', bleCharacteristicUuid);
    final connectedAt = bleConnectedAt;
    if (connectedAt != null) {
      await prefs.setString('bleConnectedAt', connectedAt.toIso8601String());
    } else {
      await prefs.remove('bleConnectedAt');
    }
    final sensorAt = lastSensorUpdateAt;
    if (sensorAt != null) {
      await prefs.setString('lastSensorUpdateAt', sensorAt.toIso8601String());
    } else {
      await prefs.remove('lastSensorUpdateAt');
    }
    await prefs.setString('sensorStatus', sensorStatus);
    await prefs.setString('userName', userName);
    await prefs.setString('emergencyContactName', emergencyContactName);
    await prefs.setString('emergencyContactPhone', emergencyContactPhone);
    await prefs.setDouble('weight', weight);
    await prefs.setDouble('height', height);
    await prefs.setInt('age', age);
    final currentBirthDate = birthDate;
    if (currentBirthDate != null) {
      await prefs.setString('birthDate', currentBirthDate.toIso8601String());
    } else {
      await prefs.remove('birthDate');
    }
    await prefs.setString('gender', gender);
    await prefs.setString('conditions', conditions);
    final acceptedAt = privacyPolicyAcceptedAt;
    if (acceptedAt != null) {
      await prefs.setString(
        'privacyPolicyAcceptedAt',
        acceptedAt.toIso8601String(),
      );
    } else {
      await prefs.remove('privacyPolicyAcceptedAt');
    }
    final currentLatitude = latitude;
    final currentLongitude = longitude;
    if (currentLatitude != null && currentLongitude != null) {
      await prefs.setDouble('latitude', currentLatitude);
      await prefs.setDouble('longitude', currentLongitude);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _warningTimer?.cancel();
    _bleSubscription?.cancel();
    _bleService.dispose();
    super.dispose();
  }
}

String _csvCell(Object? value) {
  final text = (value ?? '').toString();
  if (!text.contains(',') && !text.contains('"') && !text.contains('\n')) {
    return text;
  }
  return '"${text.replaceAll('"', '""')}"';
}
