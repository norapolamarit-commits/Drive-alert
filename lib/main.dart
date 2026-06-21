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
import 'screens/health_history_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/setup_screen.dart';
import 'services/alert_storage_service.dart';
import 'services/ble_service.dart';
import 'services/cloud_service.dart';
import 'services/location_service.dart';
import 'services/mock_data_service.dart';
import 'services/phratuma_service.dart';
import 'services/risk_analyzer.dart';

void main() {
  runApp(const VitaGuardApp());
}

class VitaGuardApp extends StatelessWidget {
  const VitaGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => VitaGuardState()..initialize(),
      child: MaterialApp(
        title: 'Vita gaurd',
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
        home: const VitaGuardGate(),
      ),
    );
  }
}

class VitaGuardGate extends StatelessWidget {
  const VitaGuardGate({super.key});

  @override
  Widget build(BuildContext context) {
    final setupDone = context.watch<VitaGuardState>().setupDone;
    return setupDone ? const VitaGuardShell() : const SetupScreen();
  }
}

class VitaGuardShell extends StatefulWidget {
  const VitaGuardShell({super.key});

  @override
  State<VitaGuardShell> createState() => _VitaGuardShellState();
}

class _VitaGuardShellState extends State<VitaGuardShell> {
  int _index = 0;

  static const _screens = [
    DashboardScreen(),
    GraphScreen(),
    AlertHistoryScreen(),
    HealthHistoryScreen(),
    ProfileScreen(),
  ];

  static const _tabLabels = [
    'Current Health Status',
    'Health Data',
    'Risk Alert Log',
    'Health History',
    'Profile',
  ];

  static const _bottomLabels = [
    'Status',
    'Data',
    'Alerts',
    'History',
    'Profile',
  ];

  static const _tabIcons = [
    Icons.watch_outlined,
    Icons.monitor_heart_outlined,
    Icons.notifications_active_outlined,
    Icons.history_outlined,
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

class VitaGuardState extends ChangeNotifier {
  final MockDataService _mockDataService = MockDataService();
  final RiskAnalyzer _riskAnalyzer = RiskAnalyzer();
  final AlertStorageService _alertStorage = AlertStorageService();
  final PhratumaService _phratumaService = PhratumaService();
  final BleService _bleService = BleService();
  final CloudService _cloudService = CloudService();
  final LocationService _locationService = LocationService();

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
          'Hello, I am Vita gaurd assistant. I can explain early warnings, sensor values, actions, and history.',
      isUser: false,
    ),
  ];

  bool setupDone = false;
  bool llmEnabled = true;
  bool mockChatbotResponse = false;
  bool cloudEnabled = false;
  String language = 'English';
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
  String cloudStatus = 'Cloud sync disabled';
  String locationStatus = 'Location not requested';
  bool requestingLocation = false;
  double? latitude;
  double? longitude;
  int deviceBattery = 96;
  DateTime? privacyPolicyAcceptedAt;

  String userName = '';
  double weight = 60;
  double height = 165;
  int age = 20;
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
    required String newGender,
    required String newConditions,
  }) async {
    userName = newName.trim();
    weight = newWeight;
    height = newHeight;
    age = newAge;
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
    required String newGender,
    required String newConditions,
  }) {
    return completeSetup(
      newName: userName,
      newWeight: newWeight,
      newHeight: newHeight,
      newAge: newAge,
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
    deviceBattery = (96 - sensorHistory.length ~/ 4).clamp(18, 96).toInt();
    currentRisk = _riskAnalyzer.analyze(data, sensorHistory);
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
        _syncAlertToCloud(alert);
      }
    }
    _syncSensorToCloud(data, currentRisk);
    notifyListeners();
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
        'deviceId': deviceId,
        'name': userName,
        'age': age,
        'weight': weight,
        'height': height,
        'gender': gender,
        'conditions': conditions,
        'latitude': latitude,
        'longitude': longitude,
        'privacyPolicyAcceptedAt': privacyPolicyAcceptedAt?.toIso8601String(),
      };

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
    deviceId = prefs.getString('deviceId') ?? deviceId;
    if (deviceId.isEmpty) {
      deviceId = 'device-${DateTime.now().microsecondsSinceEpoch}';
      await prefs.setString('deviceId', deviceId);
    }
    phratumaEndpoint = prefs.getString('phratumaEndpoint') ?? phratumaEndpoint;
    cloudBaseUrl = configuredCloudBaseUrl.isNotEmpty
        ? configuredCloudBaseUrl
        : (prefs.getString('cloudBaseUrl') ?? cloudBaseUrl);
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
    userName = prefs.getString('userName') ?? userName;
    final acceptedAtRaw = prefs.getString('privacyPolicyAcceptedAt');
    privacyPolicyAcceptedAt =
        acceptedAtRaw == null ? null : DateTime.tryParse(acceptedAtRaw);
    weight = prefs.getDouble('weight') ?? weight;
    height = prefs.getDouble('height') ?? height;
    age = prefs.getInt('age') ?? age;
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
    await prefs.setString('userName', userName);
    await prefs.setDouble('weight', weight);
    await prefs.setDouble('height', height);
    await prefs.setInt('age', age);
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
    _timer?.cancel();
    _bleSubscription?.cancel();
    _bleService.dispose();
    super.dispose();
  }
}
