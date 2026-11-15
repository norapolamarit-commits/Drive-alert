import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/alert_record.dart';
import 'models/chat_message.dart';
import 'models/risk_result.dart';
import 'models/sensor_data.dart';
import 'models/sensor_risk_sample.dart';
import 'screens/dashboard_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/device_screen.dart';
import 'screens/graph_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/login_screen.dart';
import 'screens/password_recovery_screen.dart';
import 'screens/setup_screen.dart';
import 'services/alert_storage_service.dart';
import 'services/auth_service.dart';
import 'services/ble_service.dart';
import 'services/cloud_service.dart';
import 'services/location_service.dart';
import 'services/mock_data_service.dart';
import 'services/notification_service.dart';
import 'services/phratuma_service.dart';
import 'services/secure_local_storage.dart';
import 'ui_text.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? startupError;
  try {
    await AuthService.initialize();
  } catch (_) {
    // Do not silently bypass a partially configured account system.
    startupError = 'auth_configuration';
  }
  runApp(DozApp(startupError: startupError));
}

class DozApp extends StatelessWidget {
  const DozApp({super.key, this.startupError, this.secureStore});

  final String? startupError;
  final SecureKeyValueStore? secureStore;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DozState(secureStore: secureStore)
        ..initialize(authUserId: AuthService.currentUserId),
      child: Consumer<DozState>(
        builder: (context, state, _) => MaterialApp(
          title: 'doz',
          locale: Locale(state.language == 'Thai' ? 'th' : 'en'),
          supportedLocales: const [Locale('en'), Locale('th')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF39C6A5),
              brightness: Brightness.dark,
            ),
            scaffoldBackgroundColor: const Color(0xFF080B10),
            navigationBarTheme: NavigationBarThemeData(
              backgroundColor: const Color(0xFF0D1118),
              indicatorColor: const Color(0xFF55D6A7),
              labelTextStyle:
                  WidgetStateProperty.resolveWith((states) => TextStyle(
                        color: states.contains(WidgetState.selected)
                            ? Colors.white
                            : const Color(0xFF8B93A3),
                        fontSize: 11,
                        fontWeight: states.contains(WidgetState.selected)
                            ? FontWeight.w700
                            : FontWeight.w500,
                      )),
            ),
            useMaterial3: true,
            cardTheme: CardThemeData(
              color: const Color(0xFF11141B),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF11141B),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF343B4A)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: Color(0xFF55D6A7), width: 1.5),
              ),
            ),
          ),
          home: startupError == null
              ? const DozGate()
              : const _StartupErrorScreen(),
        ),
      ),
    );
  }
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      size: 48, color: Color(0xFFFFC56A)),
                  const SizedBox(height: 16),
                  Text(
                      uiText(
                        context,
                        english: 'Account setup failed',
                        thai: 'ตั้งค่าระบบบัญชีไม่สำเร็จ',
                      ),
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  Text(
                    uiText(
                      context,
                      english:
                          'Check DOZ_SUPABASE_URL and DOZ_SUPABASE_PUBLISHABLE_KEY, then rebuild the app. Login will not be bypassed automatically.',
                      thai:
                          'ตรวจสอบ DOZ_SUPABASE_URL และ DOZ_SUPABASE_PUBLISHABLE_KEY แล้ว build แอปใหม่ ระบบจะไม่ข้ามไปโหมดที่ไม่มี login โดยอัตโนมัติ',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DozGate extends StatelessWidget {
  const DozGate({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DozState>();
    if (!state.isReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (state.initializationError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(uiText(
              context,
              english:
                  'Secure local storage is unavailable. Health data was not loaded or saved. Check device security settings and restart the app.',
              thai:
                  'พื้นที่จัดเก็บข้อมูลที่ปลอดภัยใช้งานไม่ได้ ระบบไม่ได้อ่านหรือบันทึกข้อมูลสุขภาพ โปรดตรวจการตั้งค่าความปลอดภัยของอุปกรณ์แล้วเปิดแอปใหม่',
            )),
          ),
        ),
      );
    }
    if (AuthService.isConfigured) {
      return StreamBuilder<AuthState>(
        stream: AuthService.authChanges,
        builder: (context, snapshot) {
          final authState = snapshot.data;
          if (state.passwordRecoveryPending ||
              authState?.event == AuthChangeEvent.passwordRecovery) {
            return const PasswordRecoveryScreen();
          }
          final userId =
              authState?.session?.user.id ?? AuthService.currentUserId;
          if (userId == null) return const LoginScreen();
          if (state.bindingAccount) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          if (state.authScopeId != userId) {
            // Binding notifies listeners; defer it until the current build
            // finishes so the auth gate never mutates its ancestor provider
            // while StreamBuilder is laying out the authenticated route.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted ||
                  AuthService.currentUserId != userId ||
                  state.authScopeId == userId ||
                  state.bindingAccount) {
                return;
              }
              unawaited(state.bindAuthenticatedUser(userId));
            });
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          return state.setupDone ? const DozShell() : const SetupScreen();
        },
      );
    }
    return state.setupDone ? const DozShell() : const SetupScreen();
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
    ChatScreen(),
    DeviceScreen(),
    ProfileScreen(),
  ];

  static const _tabIcons = [
    Icons.watch_outlined,
    Icons.monitor_heart_outlined,
    Icons.chat_bubble_outline,
    Icons.bluetooth_searching,
    Icons.person_outline,
  ];

  @override
  Widget build(BuildContext context) {
    final tabLabels = [
      uiText(context, english: 'Current Health Status', thai: 'สถานะสุขภาพ'),
      uiText(context,
          english: 'Health Data & History', thai: 'ข้อมูลและประวัติ'),
      uiText(context, english: 'doz Assistant', thai: 'ผู้ช่วย doz'),
      uiText(context, english: 'Connect device', thai: 'เชื่อมต่ออุปกรณ์'),
      uiText(context, english: 'Profile', thai: 'โปรไฟล์'),
    ];
    final bottomLabels = [
      uiText(context, english: 'Status', thai: 'สถานะ'),
      uiText(context, english: 'Data', thai: 'ข้อมูล'),
      uiText(context, english: 'Ask doz', thai: 'ถาม doz'),
      uiText(context, english: 'Device', thai: 'อุปกรณ์'),
      uiText(context, english: 'Profile', thai: 'โปรไฟล์'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 820;
        final content = _MainContent(
          selectedIndex: _index,
          labels: tabLabels,
          screens: _screens,
          showTopTabs: wide,
          onSelected: (index) => setState(() => _index = index),
        );

        return Scaffold(
          body: SafeArea(child: content),
          bottomNavigationBar: wide
              ? null
              : _BottomPageTabs(
                  selectedIndex: _index,
                  labels: bottomLabels,
                  icons: _tabIcons,
                  onSelected: (index) => setState(() => _index = index),
                ),
        );
      },
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
    final state = context.watch<DozState>();
    return Padding(
      padding: compact
          ? const EdgeInsets.fromLTRB(16, 12, 16, 12)
          : const EdgeInsets.fromLTRB(36, 22, 36, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF12352F),
                  borderRadius: BorderRadius.circular(14),
                ),
                child:
                    const Icon(Icons.watch_outlined, color: Color(0xFF55D6A7)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('doz',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.2,
                                )),
                    Text(labels[selectedIndex],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Color(0xFF8B93A3), fontSize: 12)),
                  ],
                ),
              ),
              _ConnectionPill(
                connected: state.bleConnected,
                freshness: state.sensorFreshnessStatus,
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: uiText(context,
                    english: 'Profile and settings', thai: 'โปรไฟล์และตั้งค่า'),
                onPressed: () => onSelected(screens.length - 1),
                icon: const Icon(Icons.account_circle_outlined),
              ),
            ],
          ),
          SizedBox(height: compact ? 12 : 18),
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
            Divider(height: compact ? 18 : 24, color: const Color(0xFF232833)),
          ],
          // Keep each destination mounted so drafts, scroll positions, and
          // in-progress form edits survive ordinary tab navigation.
          Expanded(
            child: IndexedStack(
              index: selectedIndex,
              children: screens,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill({required this.connected, required this.freshness});

  final bool connected;
  final String freshness;

  @override
  Widget build(BuildContext context) {
    final String label;
    final String accessibleLabel;
    final Color tint;
    final IconData icon;
    if (!connected) {
      label = uiText(context, english: 'DEMO', thai: 'สาธิต');
      accessibleLabel = uiText(
        context,
        english: 'Demo data; no device connected',
        thai: 'ข้อมูลสาธิต; ยังไม่ได้เชื่อมต่ออุปกรณ์',
      );
      tint = const Color(0xFFFFC56A);
      icon = Icons.bluetooth_searching;
    } else if (freshness == 'Receiving data') {
      label = uiText(context, english: 'LIVE', thai: 'สด');
      accessibleLabel = uiText(
        context,
        english: 'Device connected and sensor data is live',
        thai: 'เชื่อมต่ออุปกรณ์และกำลังรับข้อมูลเซนเซอร์',
      );
      tint = const Color(0xFF55D6A7);
      icon = Icons.bluetooth_connected;
    } else if (freshness == 'Sensor data stale') {
      label = uiText(context, english: 'STALE', thai: 'ค้าง');
      accessibleLabel = uiText(
        context,
        english: 'Device connected but sensor data is stale',
        thai: 'เชื่อมต่ออยู่แต่ข้อมูลเซนเซอร์ค้าง',
      );
      tint = const Color(0xFFFF6B72);
      icon = Icons.warning_amber_rounded;
    } else if (freshness == 'Sensor data delayed') {
      label = uiText(context, english: 'DELAYED', thai: 'ล่าช้า');
      accessibleLabel = uiText(
        context,
        english: 'Device connected; sensor data is delayed',
        thai: 'เชื่อมต่ออยู่แต่ข้อมูลเซนเซอร์ล่าช้า',
      );
      tint = const Color(0xFFFFC56A);
      icon = Icons.bluetooth_connected;
    } else {
      label = uiText(context, english: 'WAITING', thai: 'รอข้อมูล');
      accessibleLabel = uiText(
        context,
        english: 'Device connected; waiting for the first sensor reading',
        thai: 'เชื่อมต่อแล้ว กำลังรอข้อมูลเซนเซอร์ชุดแรก',
      );
      tint = const Color(0xFFFFC56A);
      icon = Icons.bluetooth_searching;
    }

    return Semantics(
      label: accessibleLabel,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.10),
            border: Border.all(color: tint.withValues(alpha: 0.30)),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: tint),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: tint,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
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
        backgroundColor: const Color(0xFF0D1118),
        indicatorColor: const Color(0xFF55D6A7),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: List.generate(
          labels.length,
          (index) => NavigationDestination(
            icon: Icon(icons[index], color: const Color(0xFFA7B0C0)),
            selectedIcon: Icon(icons[index], color: const Color(0xFF06241D)),
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
  DozState({SecureKeyValueStore? secureStore})
      : this._(secureStore: secureStore, allowUnconfiguredTestScopes: false);

  // EN: Create state for tests that inject account IDs without Supabase auth.
  // TH: สร้าง state สำหรับทดสอบที่กำหนด account ID เองโดยไม่มี Supabase auth
  DozState.forTesting({SecureKeyValueStore? secureStore})
      : this._(secureStore: secureStore, allowUnconfiguredTestScopes: true);

  // EN: Keep the test-only auth-scope override out of the production default.
  // TH: แยกการยกเว้น auth สำหรับ test ออกจากค่าเริ่มต้นที่ใช้จริง
  DozState._({
    required SecureKeyValueStore? secureStore,
    required bool allowUnconfiguredTestScopes,
  })  : _allowUnconfiguredTestScopes = allowUnconfiguredTestScopes,
        _alertStorage = AlertStorageService(secureStore: secureStore),
        _secureProfileStorage = SecureProfileStorage(store: secureStore);

  // EN: Bound the in-memory alert history to the same limit as local storage.
  // TH: จำกัดประวัติแจ้งเตือนในหน่วยความจำให้เท่ากับขอบเขตข้อมูลในเครื่อง
  static const int _maxStoredAlerts = AlertStorageService.maxEntries;

  final MockDataService _mockDataService = MockDataService();
  // EN: Permit fake account scopes only in the explicit testing constructor.
  // TH: อนุญาต scope บัญชีจำลองเฉพาะเมื่อใช้ constructor สำหรับทดสอบ
  final bool _allowUnconfiguredTestScopes;
  final AlertStorageService _alertStorage;
  final SecureProfileStorage _secureProfileStorage;
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
    riskClass: 'Demo preview',
    alertLevel: 'Unknown',
    detectedSigns: [
      'Demo sensor values are generated for interface preview only.'
    ],
    recommendation: 'No AI or risk assessment is available in demo mode.',
  );

  final List<SensorData> sensorHistory = [];
  final List<SensorRiskSample> sensorRiskHistory = [];
  final List<AlertRecord> alerts = [];
  final List<ChatMessage> chatMessages = [
    ChatMessage(
      text:
          'Hi, I can explain app status and how to use it. Replies are general information, not a medical diagnosis.',
      isUser: false,
    ),
  ];

  ChatMessage _welcomeChatMessage() => ChatMessage(
        text: language == 'Thai'
            ? 'สวัสดี ฉันช่วยอธิบายสถานะในแอปและวิธีใช้งานได้ คำตอบเป็นข้อมูลทั่วไป ไม่ใช่การวินิจฉัยโรค'
            : 'Hi, I can explain app status and how to use it. Replies are general information, not a medical diagnosis.',
        isUser: false,
      );

  void _resetChatToWelcome() {
    chatMessages
      ..clear()
      ..add(_welcomeChatMessage());
  }

  bool setupDone = false;
  bool isReady = false;
  String? initializationError;
  bool bindingAccount = false;
  bool passwordRecoveryPending = false;
  String authScopeId = 'local-demo';
  bool chatbotBusy = false;
  bool chatbotRemoteConsent = false;
  String chatbotRemoteConsentEndpoint = '';
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
  Completer<void>? _bleScanCancelSignal;
  String bleStatus = 'Mock BLE stream';
  String bleDeviceName = 'No device selected';
  String bleDeviceId = '-';
  String bleServiceUuid = '-';
  String bleCharacteristicUuid = '-';
  List<ScanResult> scannedBleDevices = const [];
  DateTime? bleConnectedAt;
  DateTime? lastSensorUpdateAt;
  bool lastReadingWasFromDevice = false;
  String sensorStatus = 'No sensor data yet';
  String _lastNotifiedFreshnessStatus = 'No sensor data yet';
  String cloudStatus =
      'Cloud sync disabled pending production privacy/security review';
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
  int? deviceBattery;
  DateTime? privacyPolicyAcceptedAt;
  String privacyPolicyVersion = 'DRAFT-1.1';

  String userName = '';
  String emergencyContactName = '';
  String emergencyContactPhone = '';
  double weight = 60;
  double height = 165;
  int age = 20;
  bool profileDetailsProvided = false;
  DateTime? birthDate;
  String gender = 'Female';
  String conditions = 'None';

  Timer? _timer;
  StreamSubscription<DozDeviceReading>? _bleSubscription;
  StreamSubscription<String>? _bleDisconnectSubscription;
  StreamSubscription<AuthState>? _authSubscription;
  Future<void>? _initializationFuture;
  Future<AccountDeletionResult>? _accountDeletionFuture;
  bool _authSessionActive = true;
  int _locationRequestEpoch =
      0; // EN: Invalidate location results from older account sessions. TH: ยกเลิกผลตำแหน่งจาก session เก่า
  final Map<String, Future<void>> _accountStorageQueues = <String,
      Future<
          void>>{}; // EN: Serialize account-scoped storage operations. TH: จัดลำดับงาน storage แยกตามบัญชี
  final Set<String> _invalidatedAccountScopes =
      <String>{}; // EN: Fence accounts that were successfully deleted. TH: กั้น scope ของบัญชีที่ลบสำเร็จแล้ว
  bool _sensorCloudSyncInFlight = false;
  bool _alertCloudSyncInFlight = false;

  Future<void> initialize({String? authUserId}) {
    // EN: Share one startup operation if the provider invokes initialization twice.
    // TH: ใช้ startup operation เดียวเมื่อ provider เรียก initialize ซ้ำ
    if (_disposed) return Future<void>.value();
    return _initializationFuture ??= _initializeSafely(authUserId: authUserId);
  }

  Future<void> _initializeSafely({String? authUserId}) async {
    try {
      await _initializeInternal(authUserId: authUserId);
    } catch (_) {
      // EN: Never fall back to plaintext if platform secure storage fails.
      // TH: ห้ามย้อนกลับไปใช้ plaintext หาก secure storage ของระบบล้มเหลว
      if (_disposed) return;
      _timer?.cancel();
      initializationError = 'secure_local_storage';
      isReady = true;
      _notifyIfAlive();
    }
  }

  Future<void> _initializeInternal({String? authUserId}) async {
    _authSessionActive = !AuthService.isConfigured || authUserId != null;
    final initializationScope = authUserId ?? 'local-demo';
    if (AuthService.isConfigured) {
      _authSubscription = AuthService.authChanges.listen((authState) {
        if (_disposed) return;
        if (authState.event == AuthChangeEvent.passwordRecovery) {
          passwordRecoveryPending = true;
          _notifyIfAlive();
        } else if (authState.event == AuthChangeEvent.signedOut) {
          passwordRecoveryPending = false;
          unawaited(clearRuntimeDataOnSignOut());
        }
      }, onError: (Object error, StackTrace stackTrace) {
        // Auth network/refresh errors are surfaced by DozGate's StreamBuilder.
        // This secondary state listener must handle errors to avoid an
        // unhandled stream exception while retaining the current session.
      });
    }
    authScopeId = initializationScope;
    _alertStorage.setScope(authScopeId);
    await _loadSettings(authUserId);
    if (_disposed) return;
    isReady = true;
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
    if (authScopeId == initializationScope &&
        _isAuthScopeActive(initializationScope)) {
      final loadedAlerts = await _alertStorage.loadAlerts();
      if (_disposed ||
          authScopeId != initializationScope ||
          !_isAuthScopeActive(initializationScope)) {
        return;
      }
      alerts
        ..clear()
        ..addAll(loadedAlerts);
    }
    await _initializeNotifications();
    if (_disposed) return;
    _startMockLoop();
    _bleSubscription =
        _bleService.deviceReadingStream.listen(_updateFromDevice);
    _bleDisconnectSubscription =
        _bleService.deviceDisconnectedStream.listen(_handleBleDisconnect);
    _notifyIfAlive();
  }

  void _startMockLoop() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_disposed) return;
      final mayRunDemo = !AuthService.isConfigured ||
          (AuthService.currentUserId != null &&
              _authSessionActive &&
              !bindingAccount);
      if (!bleConnected && !scanningBle && mayRunDemo) {
        updateSensorData(_mockDataService.nextAuto());
      } else if (bleConnected) {
        refreshSensorFreshness();
      }
    });
  }

  /// Publish UI updates only when the live packet freshness state changes.
  void refreshSensorFreshness() {
    if (!bleConnected) return;
    final current = sensorFreshnessStatus;
    if (current == _lastNotifiedFreshnessStatus) return;
    _lastNotifiedFreshnessStatus = current;
    _notifyIfAlive();
  }

  void _handleBleDisconnect(String _) {
    if (_disposed) return;
    bleConnected = false;
    bleConnectedAt = null;
    deviceBattery = null;
    lastReadingWasFromDevice = false;
    lastSensorUpdateAt = null;
    _lastNotifiedFreshnessStatus = 'No sensor data yet';
    bleStatus = 'BLE connection lost; demo data mode';
    sensorStatus = 'Device disconnected; demo data is shown';
    currentRisk = const RiskResult(
      riskClass: 'Device disconnected',
      alertLevel: 'Unknown',
      detectedSigns: ['The BLE connection to the device was lost.'],
      recommendation: 'Reconnect the device. Demo values are not sensor data.',
    );
    aiAdvice = '';
    unawaited(_saveSettings());
    _notifyIfAlive();
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
    bool newProfileDetailsProvided = true,
  }) async {
    userName = newName.trim();
    weight = newWeight;
    height = newHeight;
    age = newAge;
    birthDate = newBirthDate ?? birthDate;
    gender = newGender;
    conditions = newConditions.trim().isEmpty ? 'None' : newConditions.trim();
    profileDetailsProvided = newProfileDetailsProvided;
    privacyPolicyAcceptedAt =
        newPrivacyPolicyAcceptedAt ?? privacyPolicyAcceptedAt;
    setupDone = true;
    bleStatus = bleConnected ? bleStatus : 'Mock BLE stream connected';
    await _saveSettings();
    _notifyIfAlive();
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
      newProfileDetailsProvided: true,
    );
  }

  Future<void> resetSetup() async {
    setupDone = false;
    await _saveSettings();
    _notifyIfAlive();
  }

  Future<void> bindAuthenticatedUser(String authenticatedUserId) async {
    if (authenticatedUserId.isEmpty ||
        (authScopeId == authenticatedUserId && _authSessionActive)) {
      return;
    }
    if (bindingAccount) {
      // EN: Let the active bind finish and reconcile with Auth's latest user afterward. TH: รอ bind ปัจจุบันแล้วตรวจผู้ใช้ล่าสุดจาก Auth ภายหลัง
      return; // EN: Avoid concurrent mutation of shared account state. TH: ป้องกันแก้ state บัญชีร่วมกันพร้อมกัน
    } // EN: Continue with a single account bind. TH: ทำ bind บัญชีเพียงรายการเดียว
    bindingAccount = true;
    _locationRequestEpoch++; // EN: Invalidate pending location requests before switching accounts. TH: ยกเลิกคำขอตำแหน่งที่ค้างก่อนสลับบัญชี
    requestingLocation =
        false; // EN: Reset the prior account's location progress state. TH: รีเซ็ตสถานะขอตำแหน่งของบัญชีก่อน
    _authSessionActive = true;
    _notifyIfAlive();
    try {
      if (authScopeId != authenticatedUserId &&
          (bleConnected || _bleService.isConnected)) {
        try {
          await _bleService.disconnect();
        } catch (_) {
          // Clear the prior account's runtime state even if BLE cleanup fails.
        }
      }
      if (!_isAuthScopeActive(authenticatedUserId)) {
        // EN: Stop if Auth changed while disconnecting the prior device. TH: หยุดหาก Auth เปลี่ยนระหว่างตัดอุปกรณ์เดิม
        return; // EN: Do not bind a stale identity. TH: ไม่ bind identity ที่ล้าสมัย
      } // EN: Continue only while this identity remains active. TH: ทำต่อเมื่อ identity นี้ยัง active
      bleConnected = false;
      bleConnectedAt = null;
      lastReadingWasFromDevice = false;
      lastSensorUpdateAt = null;
      _lastNotifiedFreshnessStatus = 'No sensor data yet';
      deviceBattery = null;
      bleDeviceName = 'No device selected';
      bleDeviceId = '-';
      bleStatus =
          'Mock BLE stream connected'; // EN: Do not retain the previous account's device status. TH: ไม่คงสถานะอุปกรณ์ของบัญชีก่อนหน้า
      sensorStatus =
          'No sensor data yet'; // EN: The new account has no current sensor reading. TH: บัญชีใหม่ยังไม่มีค่าจากเซนเซอร์
      authScopeId = authenticatedUserId;
      _alertStorage.setScope(authenticatedUserId);
      userId = authenticatedUserId;
      deviceId = '';
      setupDone = false;
      userName = '';
      weight = 60;
      height = 165;
      age = 20;
      profileDetailsProvided = false;
      birthDate = null;
      gender = 'Female';
      conditions = 'None';
      emergencyContactName = '';
      emergencyContactPhone = '';
      latitude =
          null; // EN: Clear the prior account's coordinates before loading the new profile. TH: ล้างพิกัดบัญชีก่อนโหลดโปรไฟล์ใหม่
      longitude =
          null; // EN: Clear the prior account's coordinates before loading the new profile. TH: ล้างพิกัดบัญชีก่อนโหลดโปรไฟล์ใหม่
      locationStatus =
          'Location not requested'; // EN: Do not retain the previous account's location status. TH: ไม่คงสถานะตำแหน่งของบัญชีก่อน
      privacyPolicyAcceptedAt = null;
      chatbotRemoteConsent = false;
      chatbotRemoteConsentEndpoint = '';
      cloudEnabled = false;
      alerts.clear();
      sensorHistory.clear();
      sensorRiskHistory.clear();
      _resetChatToWelcome();
      currentSensor = SensorData(
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
      currentRisk = const RiskResult(
        riskClass: 'AI analysis unavailable',
        alertLevel: 'Unknown',
        detectedSigns: ['No current reading from a physical device.'],
        recommendation:
            'Connect the wearable to receive data. No risk assessment is available yet.',
      );
      await _loadSettings(authenticatedUserId);
      if (!_isAuthScopeActive(authenticatedUserId)) {
        // EN: Stop if account settings finished after an identity change. TH: หยุดหากโหลดค่าตั้งเสร็จหลัง identity เปลี่ยน
        return; // EN: Keep stale account data out of the active UI. TH: กันข้อมูลบัญชีเก่าออกจาก UI ปัจจุบัน
      } // EN: Continue loading this active account's history. TH: โหลดประวัติบัญชีที่ active ต่อ
      await _alertStorage.migrateLegacyHistoryIfNeeded(
          scopeId: authenticatedUserId);
      if (!_isAuthScopeActive(authenticatedUserId)) {
        // EN: Recheck after history migration. TH: ตรวจซ้ำหลัง migrate ประวัติ
        return; // EN: Do not continue stale account hydration. TH: ไม่เติมข้อมูลบัญชีเก่าต่อ
      } // EN: Continue for the active account. TH: ทำต่อสำหรับบัญชี active
      final loadedAlerts = await _alertStorage
          .loadAlerts(); // EN: Read this account's history into a local result. TH: อ่านประวัติบัญชีนี้ไว้ในตัวแปร local
      if (!_isAuthScopeActive(authenticatedUserId)) {
        // EN: Recheck after the secure history read. TH: ตรวจซ้ำหลังอ่าน secure history
        return; // EN: Do not apply old history to the current session. TH: ไม่ใช้ประวัติเก่ากับ session ปัจจุบัน
      } // EN: Continue applying history for the same account. TH: นำประวัติของบัญชีเดิมมาใช้ต่อ
      alerts
        ..clear()
        ..addAll(
            loadedAlerts); // EN: Replace in-memory history only after validating account ownership. TH: แทนที่ประวัติในหน่วยความจำหลังยืนยันเจ้าของแล้ว
      await _saveSettings();
    } catch (_) {
      if (_isAuthScopeActive(authenticatedUserId)) {
        // EN: Show storage failure only for the still-active account. TH: แสดง storage error เฉพาะบัญชีที่ยัง active
        initializationError =
            'secure_local_storage'; // EN: Keep internal storage details out of the user-facing message. TH: ไม่เปิดเผยรายละเอียด storage ภายในแก่ผู้ใช้
      } // EN: Ignore errors from a bind made stale by account switching. TH: ข้าม error จาก bind ที่ล้าสมัยเพราะสลับบัญชี
    } finally {
      bindingAccount = false;
      final latestUserId = AuthService
          .currentUserId; // EN: Read the provider's identity after releasing the bind lock. TH: อ่าน identity ล่าสุดหลังปลดล็อก bind
      if (latestUserId != null && latestUserId != authScopeId) {
        // EN: Detect an account switch that arrived during this bind. TH: ตรวจการสลับบัญชีที่เกิดระหว่าง bind
        unawaited(bindAuthenticatedUser(
            latestUserId)); // EN: Bind the latest provider identity instead of leaving stale state. TH: bind identity ล่าสุดแทนการคง state เก่า
      } // EN: Finish reconciliation with the current Auth identity. TH: จบการปรับ state ให้ตรงกับ identity ปัจจุบัน
    }
    _notifyIfAlive();
  }

  Future<void> logout() async {
    if (!AuthService.isConfigured) return;
    await AuthService.signOut();
  }

  Future<AccountDeletionResult> deleteAccount() {
    // EN: Share one destructive request while it is in progress. TH: ใช้คำขอลบรายการเดียวระหว่างที่กำลังทำงาน
    if (_disposed) return Future.value(AccountDeletionResult.failed);
    final activeOperation = _accountDeletionFuture;
    if (activeOperation != null) return activeOperation;
    final operation = _deleteAccountOnce();
    _accountDeletionFuture = operation;
    return operation.whenComplete(() {
      if (identical(_accountDeletionFuture, operation)) {
        _accountDeletionFuture = null;
      }
    });
  }

  Future<AccountDeletionResult> _deleteAccountOnce() async {
    final accountId = AuthService.currentUserId;
    final token = AuthService.currentAccessToken;
    if (!AuthService.isConfigured || accountId == null || token == null) {
      return AccountDeletionResult.notConfigured;
    }
    final result = await _cloudService.deleteAccount(
      baseUrl: cloudBaseUrl,
      bearerToken: token,
    );
    if (result != AccountDeletionResult.deleted) return result;

    _invalidatedAccountScopes.add(
        accountId); // EN: Block new local writes after remote deletion succeeds. TH: กัน write ใหม่หลังลบบัญชีบน server สำเร็จ
    _alertStorage.invalidateScope(
        accountId); // EN: Fence alert writes for the deleted account. TH: กั้นการเขียน alert ของบัญชีที่ลบแล้ว
    final stillDeletingAccount = AuthService.currentUserId == accountId;
    if (stillDeletingAccount) {
      // EN: Clear sensitive in-memory state immediately after server confirmation, before fallible disk cleanup.
      // TH: ล้างข้อมูลอ่อนไหวในหน่วยความจำทันทีหลัง server ยืนยัน ก่อนเริ่มล้าง disk ที่อาจผิดพลาด
      await clearRuntimeDataOnSignOut();
      try {
        // EN: Supabase clears its local session before attempting remote revocation.
        // TH: Supabase ล้าง session ในเครื่องก่อนพยายามเพิกถอน session บน server
        await AuthService.signOut();
      } catch (_) {
        // EN: Continue cleanup because remote account deletion already succeeded.
        // TH: ทำ cleanup ต่อเพราะ server ยืนยันการลบบัญชีแล้ว
      }
    }
    final pendingStorageOperation = _accountStorageQueues[
        accountId]; // EN: Capture any account storage operation already in progress. TH: จับ future ของ storage operation ของบัญชีที่กำลังทำอยู่
    if (pendingStorageOperation != null) {
      // EN: Wait before clearing the account namespace. TH: รอก่อนล้าง namespace ของบัญชี
      try {
        // EN: Continue local deletion even if a prior save failed. TH: ทำ local deletion ต่อแม้ save ก่อนหน้าล้มเหลว
        await pendingStorageOperation; // EN: Let queued storage work finish before deleting its data. TH: รอ storage ที่เข้าคิวจบก่อนลบข้อมูล
      } catch (_) {
        // EN: Keep storage errors from bypassing the deletion cleanup. TH: ป้องกัน storage error ข้ามขั้นตอนล้างข้อมูล
        // EN: A failed save leaves no reason to keep its local partial data. TH: save ที่ล้มเหลวไม่ใช่เหตุให้เก็บข้อมูลบางส่วนไว้
      } // EN: Finish waiting for the earlier local write. TH: จบการรอ local write ก่อนหน้า
    } // EN: Continue once no captured settings write is active. TH: ทำต่อเมื่อไม่มี settings write ที่จับไว้กำลังทำงาน

    var localCleanupSucceeded = true;
    // EN: Attempt each local store independently so one failure cannot skip the others.
    // TH: ล้าง local store แต่ละแหล่งแยกกัน เพื่อไม่ให้จุดหนึ่งล้มแล้วข้ามจุดอื่น
    try {
      final prefs = await SharedPreferences.getInstance();
      final prefix = 'doz.$accountId.';
      for (final key
          in prefs.getKeys().where((key) => key.startsWith(prefix)).toList()) {
        if (!await prefs.remove(key)) localCleanupSucceeded = false;
      }
    } catch (_) {
      localCleanupSucceeded = false;
    }
    try {
      await _alertStorage.clearAlerts(scopeId: accountId);
    } catch (_) {
      localCleanupSucceeded = false;
    }
    try {
      await _secureProfileStorage.clearProfile(accountId);
    } catch (_) {
      localCleanupSucceeded = false;
    }
    return localCleanupSucceeded
        ? AccountDeletionResult.deleted
        : AccountDeletionResult.deletedLocalCleanupFailed;
  }

  /// Drop account-specific health data from memory after logout while keeping
  /// the account's locally stored history available for its next verified login.
  Future<void> clearRuntimeDataOnSignOut() async {
    if (_disposed || !_authSessionActive) return;
    _authSessionActive = false;
    _locationRequestEpoch++; // EN: Prevent an earlier location response from restoring cleared data. TH: กันผลตำแหน่งเก่ากลับมาเติมข้อมูลที่ล้างแล้ว
    requestingLocation =
        false; // EN: Clear the old session's location progress indicator. TH: ล้างสถานะกำลังขอตำแหน่งของ session เดิม
    _warningTimer?.cancel();
    _warningTimer = null;
    _warningEpisodeAcknowledged = false;
    chatbotRemoteConsent = false;
    chatbotRemoteConsentEndpoint = '';
    setupDone = false;
    userId = '';
    userName = '';
    profileDetailsProvided = false;
    deviceId = '';
    weight = 60;
    height = 165;
    age = 20;
    birthDate = null;
    gender = 'Female';
    conditions = 'None';
    emergencyContactName = '';
    emergencyContactPhone = '';
    latitude = null;
    longitude = null;
    locationStatus = 'Location not requested';
    bleConnected = false;
    bleConnectedAt = null;
    lastReadingWasFromDevice = false;
    bleDeviceName = 'No device selected';
    bleDeviceId = '-';
    deviceBattery = null;
    lastSensorUpdateAt = null;
    _lastNotifiedFreshnessStatus = 'No sensor data yet';
    sensorHistory.clear();
    sensorRiskHistory.clear();
    alerts.clear();
    aiAdvice = '';
    aiAdviceCause = '';
    aiAdviceDisclaimer = '';
    _lastAdviceFor = '';
    chatMessages
      ..clear()
      ..add(ChatMessage(
        text: language == 'Thai'
            ? 'ลงชื่อออกแล้ว ข้อมูลสุขภาพถูกนำออกจากหน่วยความจำของแอป'
            : 'Signed out. Health data has been cleared from app memory.',
        isUser: false,
      ));
    currentSensor = SensorData(
      heartRate: 0,
      spo2: 0,
      gsr: 0,
      temperature: 0,
      accelX: 0,
      accelY: 0,
      accelZ: 0,
      gyroX: 0,
      gyroY: 0,
      gyroZ: 0,
    );
    currentRisk = const RiskResult(
      riskClass: 'Signed out',
      alertLevel: 'Unknown',
      detectedSigns: ['No active account session.'],
      recommendation: 'Sign in to view account-specific data.',
    );
    sensorStatus = 'Signed out; account data hidden';
    bleStatus = 'Signed out; device disconnected';
    _notifyIfAlive();
    try {
      await _bleService.disconnect();
    } catch (_) {
      // The account is already signed out; UI state remains cleared.
    }
  }

  /// โหมด mock/demo แสดงเฉพาะข้อมูลจำลองและไม่คำนวณผลความเสี่ยง
  /// เพื่อไม่ให้ข้อมูลตัวอย่างถูกเข้าใจว่าเป็นผล AI หรือคำแนะนำสุขภาพจริง
  Future<void> updateSensorData(SensorData data) async {
    const demoPreview = RiskResult(
      riskClass: 'Demo preview',
      alertLevel: 'Unknown',
      detectedSigns: [
        'Demo sensor values are generated for interface preview only.'
      ],
      recommendation: 'No AI or risk assessment is available in demo mode.',
    );
    await _applyReading(data, demoPreview, isDemoData: true);
  }

  /// โหมดเชื่อมต่ออุปกรณ์จริง: ความเสี่ยง (Safe/Watch/Warning/Emergency) **คำนวณบนบอร์ดแล้ว**
  /// (spec: "device is the standalone safety source of truth") — แอปแค่แปลผลลัพธ์เป็นข้อความ
  /// แสดงผล ไม่ตัดสินใจเอง ต่างจาก `updateSensorData` (mock path) ข้างบน
  Future<void> _updateFromDevice(DozDeviceReading reading) async {
    if (AuthService.isConfigured &&
        (!_authSessionActive || AuthService.currentUserId == null)) {
      return;
    }
    if (!reading.analysisAvailable || reading.riskResult == null) {
      // EN: Keep raw telemetry out of the AI/risk-alert path. TH: แยก telemetry ดิบออกจากเส้นทาง AI/แจ้งเตือนความเสี่ยง
      currentSensor = reading
          .sensorData; // EN: Update the live sensor values only. TH: อัปเดตเฉพาะค่าที่รับจาก sensor
      lastReadingWasFromDevice = true;
      currentRisk = const RiskResult(
        // EN: Show an explicit unknown state instead of a false Safe/alert result. TH: แสดงสถานะไม่ทราบผลแทนการแสดง Safe หรือแจ้งเตือนที่ไม่มีหลักฐาน
        riskClass: 'AI analysis unavailable',
        alertLevel: 'Unknown',
        detectedSigns: ['Connected to ESP32; raw sensor telemetry received.'],
        recommendation:
            'This firmware only streams sensor data; on-device AI inference is not integrated yet.',
      );
      deviceBattery =
          null; // EN: Battery percentage is not part of this telemetry protocol. TH: โปรโตคอล telemetry นี้ไม่ได้ส่งเปอร์เซ็นต์แบตเตอรี่
      lastSensorUpdateAt = DateTime
          .now(); // EN: Record phone receive time. TH: บันทึกเวลาที่โทรศัพท์รับข้อมูล
      _lastNotifiedFreshnessStatus = sensorFreshnessStatus;
      sensorStatus =
          'BLE raw telemetry received • AI unavailable'; // EN: Distinguish transport success from analysis. TH: แยกสถานะรับข้อมูลได้ออกจากการวิเคราะห์
      aiAdvice =
          ''; // EN: Clear advice when this firmware provides telemetry without AI results. TH: ลบคำแนะนำเมื่อ firmware ส่ง telemetry โดยไม่มีผล AI
      aiAdviceCause =
          ''; // EN: Clear the cause associated with the unavailable result. TH: ลบสาเหตุที่ผูกกับผลซึ่งไม่มี
      aiAdviceDisclaimer =
          ''; // EN: Clear disclaimer metadata from the prior result. TH: ลบ disclaimer จากผลก่อนหน้า
      _lastAdviceFor =
          ''; // EN: Reset the advice status cache for any later capable firmware. TH: ล้าง cache สถานะคำแนะนำสำหรับ firmware ที่รองรับในอนาคต
      sensorHistory.add(reading
          .sensorData); // EN: Keep received readings in local sensor history. TH: เก็บค่าที่รับไว้ในประวัติ sensor ภายในแอป
      if (sensorHistory.length > 240) {
        sensorHistory.removeAt(
            0); // EN: Bound in-memory history. TH: จำกัดประวัติในหน่วยความจำ
      }
      sensorRiskHistory.add(SensorRiskSample(
          sensorData: reading.sensorData,
          riskResult:
              currentRisk)); // EN: Record that no risk decision accompanied this sample. TH: บันทึกว่าตัวอย่างนี้ไม่มีผลประเมินความเสี่ยง
      if (sensorRiskHistory.length > 240) {
        sensorRiskHistory.removeAt(
            0); // EN: Bound in-memory history. TH: จำกัดประวัติในหน่วยความจำ
      }
      _notifyIfAlive(); // EN: Refresh the app with telemetry and the unknown-analysis state. TH: แจ้ง UI ให้อัปเดต telemetry และสถานะยังไม่วิเคราะห์
      return; // EN: Do not create alerts or run phone-side AI on raw device telemetry. TH: ไม่สร้าง alert และไม่รัน AI บนโทรศัพท์จาก telemetry ดิบ
    }
    lastReadingWasFromDevice = true;
    await _applyReading(reading.sensorData, reading.riskResult!,
        batteryOverride: reading.battery);
  }

  Future<void> _applyReading(SensorData data, RiskResult risk,
      {int? batteryOverride, bool isDemoData = false}) async {
    lastReadingWasFromDevice = !isDemoData;
    currentSensor = data;
    lastSensorUpdateAt = DateTime.now();
    _lastNotifiedFreshnessStatus = sensorFreshnessStatus;
    sensorStatus = _sensorStatusFor(data);
    deviceBattery = batteryOverride;
    currentRisk = risk;
    // TH: ตัวจับเวลายกระดับ 30 วิฝั่งแอปใช้เฉพาะตอน "ไม่ได้เชื่อมต่ออุปกรณ์จริง" (mock/demo)
    //     เท่านั้น — ตอนเชื่อมต่อจริงแล้ว เฟิร์มแวร์เป็นผู้ตัดสินใจ escalation นี้เองอยู่แล้ว
    //     (spec R5: on-device 30s no-response timeout) ถ้าให้แอปจับเวลาซ้ำอีกชุดจะเกิด
    //     escalation สองระบบที่อาจ race กัน/ให้เหตุผลคนละอย่างกันสำหรับเหตุการณ์เดียว
    // EN: the app's own 30s escalation timer is only used when NOT really connected to a
    //     device (mock/demo) -- once truly connected, the firmware already owns this exact
    //     escalation decision (spec R5: on-device 30s no-response timeout). Running a second,
    //     duplicate timer in the app would create two escalation systems that could race or
    //     give different reasons for the same event.
    if (!bleConnected && !isDemoData) {
      _trackWarningEscalation(currentRisk);
    }
    sensorHistory.add(data);
    if (sensorHistory.length > 240) sensorHistory.removeAt(0);
    sensorRiskHistory
        .add(SensorRiskSample(sensorData: data, riskResult: currentRisk));
    if (sensorRiskHistory.length > 240) sensorRiskHistory.removeAt(0);

    if (!isDemoData && currentRisk.shouldStoreAlert) {
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
        if (!isDemoData) {
          await _persistAlertHistory();
          _showAlertNotification(alert);
          _syncAlertToCloud(alert);
        }
      }
    }
    if (!isDemoData) {
      _syncSensorToCloud(data, currentRisk);
      _refreshAdvice(data, currentRisk);
    }
    _notifyIfAlive();
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
    if (_warningTimer != null) {
      return; // episode นี้กำลังถูกติดตามอยู่แล้ว — อย่ารีเซ็ต
    }
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
    await _persistAlertHistory();
    if (_disposed) return;
    // อัปเดตสถานะปัจจุบันด้วย — ไม่งั้นหน้า Dashboard ยังโชว์ Warning เดิม
    // ทั้งที่ประวัติแจ้งเตือนมี Emergency แล้ว (เห็นแค่ถ้าเข้าไปดู Alert History)
    currentRisk = escalatedRisk;
    _showAlertNotification(escalated);
    _syncAlertToCloud(escalated);
    _notifyIfAlive();
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
        _notifyIfAlive();
      }
      return;
    }
    // ส่งข้อมูลสุขภาพไปขอคำแนะนำได้เฉพาะเมื่อผู้ใช้ login และยินยอม chatbot
    // แบบ remote สำหรับ endpoint นี้แล้ว; หากไม่ยินยอมให้ใช้คำแนะนำในเครื่อง
    // เรียกเฉพาะเมื่อสถานะเปลี่ยนเพื่อหลีกเลี่ยงการยิง request ซ้ำ
    if (!hasFreshLiveSensorData) {
      // EN: Do not send demo, cached, future-dated, or stale readings to remote advice. TH: ห้ามส่งค่าจำลอง ค้างเวลา อนาคต หรือเก่าไปขอคำแนะนำระยะไกล
      if (aiAdvice.isNotEmpty || aiAdviceCause.isNotEmpty) {
        // EN: Clear advice tied to readings that are no longer fresh. TH: ลบคำแนะนำที่อิงค่าซึ่งไม่สดแล้ว
        aiAdvice = '';
        aiAdviceCause = '';
        aiAdviceDisclaimer = '';
        _lastAdviceFor = '';
        _notifyIfAlive();
      }
      return;
    }
    if (risk.riskClass == _lastAdviceFor ||
        !chatbotRemoteConsentValid ||
        AuthService.currentAccessToken == null) {
      return;
    }
    final approvedApiBase = PhratumaService.chatApiBaseUrl(phratumaEndpoint);
    if (approvedApiBase == null) return;
    _lastAdviceFor = risk.riskClass;

    final sensor =
        'HR ${data.heartRate} bpm, SpO2 ${data.spo2}%, HRV ${data.ecgHrv.toStringAsFixed(0)} ms, '
        'GSR ${data.gsr.toStringAsFixed(0)}, Temp ${data.temperature.toStringAsFixed(1)}°C';
    final result = await _cloudService.fetchAdvice(
      baseUrl: approvedApiBase,
      status: risk.riskClass,
      alertLevel: risk.alertLevel,
      sensor: sensor,
      bearerToken: AuthService.currentAccessToken!,
    );
    if (result != null &&
        _lastAdviceFor == risk.riskClass &&
        chatbotRemoteConsentValid &&
        hasFreshLiveSensorData) {
      aiAdvice = result.advice;
      aiAdviceCause = result.cause;
      aiAdviceDisclaimer = result.disclaimer;
      _notifyIfAlive();
    }
  }

  Future<void> respondToLatestAlert(String response) async {
    if (alerts.isEmpty) return;
    await respondToAlert(alerts.first.id, response);
  }

  Future<void> _persistAlertHistory() async {
    if (alerts.length > _maxStoredAlerts) {
      alerts.removeRange(_maxStoredAlerts, alerts.length);
    }
    await _alertStorage.saveAlerts(alerts);
  }

  Future<void> respondToAlert(String id, String response) async {
    final index = alerts.indexWhere((item) => item.id == id);
    if (index == -1) return;
    alerts[index] = alerts[index].copyWith(userResponse: response);
    await _persistAlertHistory();
    // ตอบรับ alert ล่าสุด (ที่แสดงอยู่) ระหว่าง episode ที่กำลังติดตาม → เลื่อนกำหนด
    // ยกระดับออกไปอีก 30 วิ (ตัวจับเวลาใหม่จะถูกตั้งในรอบ updateSensorData ถัดไป)
    if (alerts.isNotEmpty && id == alerts.first.id) {
      _warningEpisodeAcknowledged = true;
      _warningTimer?.cancel();
      _warningTimer = null;
      // TH: ถ้าเชื่อมต่ออุปกรณ์จริงอยู่ ต้องส่ง DOZ_CMD_ACK กลับไปที่บอร์ดด้วย ไม่งั้นตัว
      //     จับเวลา 30 วิฝั่งเฟิร์มแวร์เอง (ซึ่งเป็นตัวที่ตัดสินใจ escalation จริง) จะไม่รู้ว่า
      //     ผู้ใช้ตอบรับแล้ว แล้วยกระดับเป็น Emergency เองอยู่ดีทั้งที่ผู้ใช้กดตอบรับในแอปแล้ว
      // EN: if a real device is connected, must also send DOZ_CMD_ACK back to the board --
      //     otherwise the firmware's OWN 30s timer (which is what actually decides the
      //     escalation) has no idea the user acknowledged, and will still escalate to
      //     Emergency even though the user already responded in the app.
      if (bleConnected) {
        unawaited(_bleService.sendAck());
      }
    }
    _notifyIfAlive();
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
    _notifyIfAlive();
  }

  Future<void> askChatbot(String message) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;
    if (trimmed.length > 2000) {
      chatMessages.add(ChatMessage(
        text: language == 'Thai'
            ? 'คำถามยาวเกินไป กรุณาย่อให้ไม่เกิน 2,000 ตัวอักษร'
            : 'Your question is too long. Please shorten it to 2,000 characters or fewer.',
        isUser: false,
      ));
      _notifyIfAlive();
      return;
    }
    chatMessages.add(ChatMessage(text: trimmed, isUser: true));
    chatbotBusy = true;
    _notifyIfAlive();

    final requestEndpoint =
        phratumaEndpoint; // EN: Snapshot the destination for this request. TH: เก็บปลายทาง ณ เวลาส่งคำขอนี้
    final requestUsesRemoteAi =
        llmEnabled && // EN: Require the remote-AI feature to be enabled. TH: ต้องเปิดใช้ AI ระยะไกล
            chatbotRemoteConsentValid && // EN: Require consent for the current endpoint. TH: ต้องยินยอมสำหรับ endpoint ปัจจุบัน
            AuthService.currentAccessToken !=
                null && // EN: Require an authenticated session. TH: ต้องมี session ที่ยืนยันตัวตนแล้ว
            !mockChatbotResponse; // EN: Exclude explicitly selected local/mock mode. TH: ไม่นับโหมด local/mock ที่ผู้ใช้เลือก
    try {
      final answer = await _phratumaService.ask(
        endpoint: phratumaEndpoint,
        model: modelName,
        userMessage: trimmed,
        sensorData: currentSensor,
        riskResult: currentRisk,
        isLiveDeviceData: hasFreshLiveSensorData,
        enabled: llmEnabled && chatbotRemoteConsentValid,
        useMockResponse: mockChatbotResponse || !chatbotRemoteConsentValid,
        bearerToken: AuthService.currentAccessToken,
        language: language,
        // Do not send profile identifiers or historical alerts unless a
        // future feature has a separate, explicit consent for that data.
      );
      if (requestUsesRemoteAi && // EN: Apply the post-response check only to requests sent remotely. TH: ตรวจหลัง response เฉพาะคำขอที่ส่งระยะไกล
          (!chatbotRemoteConsentValid || // EN: Detect revoked or invalidated consent. TH: ตรวจ consent ที่ถูกถอนหรือหมดผล
              phratumaEndpoint != requestEndpoint)) {
        // EN: Detect a changed destination. TH: ตรวจว่าปลายทางเปลี่ยนหรือไม่
        // EN: Do not display a remote result after consent or destination changes. TH: ไม่แสดงผลจากระบบระยะไกลหลังถอน consent หรือเปลี่ยนปลายทาง
        chatMessages.add(ChatMessage(
          text: language ==
                  'Thai' // EN: Choose the notice in the current app language. TH: เลือกข้อความตามภาษาปัจจุบันของแอป
              ? 'ยกเลิกการแสดงคำตอบจากเซิร์ฟเวอร์ เพราะมีการเปลี่ยนการอนุญาตหรือปลายทาง' // EN: Explain that the remote answer was hidden. TH: แจ้งว่าซ่อนคำตอบจาก server
              : 'The server response was hidden because consent or the destination changed.', // EN: English equivalent of the notice. TH: ข้อความแจ้งภาษาอังกฤษ
          isUser: false,
        ));
      } else {
        chatMessages.add(ChatMessage(text: answer, isUser: false));
      }
    } finally {
      chatbotBusy = false;
      _notifyIfAlive();
    }
  }

  bool get chatbotRemoteConfigured {
    final endpoint = Uri.tryParse(phratumaEndpoint);
    return endpoint != null &&
        !endpoint.host.contains('example.com') &&
        PhratumaService.isValidRemoteChatEndpoint(phratumaEndpoint);
  }

  Future<bool> checkChatbotEndpoint(String endpoint) => _phratumaService.checkReady(
      chatEndpoint:
          endpoint); // EN: Require API Auth readiness before marking remote chat available. TH: ต้องตรวจความพร้อม Auth ก่อนระบุว่าแชตระยะไกลพร้อม

  bool get chatbotRemoteAvailable =>
      chatbotRemoteConfigured && AuthService.currentAccessToken != null;

  /// True only while physical BLE data is fresh. / จริงเฉพาะเมื่อข้อมูล BLE จริงยังใหม่อยู่
  bool get hasFreshLiveSensorData {
    final observedAt =
        lastSensorUpdateAt; // EN: Capture the latest device timestamp once. TH: อ่านเวลาข้อมูลอุปกรณ์ล่าสุดครั้งเดียว
    if (!bleConnected || !lastReadingWasFromDevice || observedAt == null) {
      return false; // EN: Require a connected BLE device, device-origin data, and a known timestamp. TH: ต้องเชื่อม BLE มีข้อมูลจากอุปกรณ์จริง และมี timestamp
    } // EN: Finish the live-data precondition guard. TH: จบการตรวจเงื่อนไขก่อนใช้ข้อมูลสด
    final age = DateTime.now().difference(
        observedAt); // EN: Calculate the reading age against the current clock. TH: คำนวณอายุข้อมูลเทียบกับเวลาปัจจุบัน
    return !age.isNegative &&
        age <=
            const Duration(
                seconds:
                    10); // EN: Reject future timestamps and data older than ten seconds. TH: ปฏิเสธ timestamp อนาคตและข้อมูลเกินสิบวินาที
  }

  bool get chatbotRemoteConsentValid =>
      chatbotRemoteAvailable &&
      chatbotRemoteConsent &&
      chatbotRemoteConsentEndpoint == phratumaEndpoint;

  Future<void> setChatbotRemoteConsent(bool accepted) async {
    chatbotRemoteConsent = accepted && chatbotRemoteAvailable;
    chatbotRemoteConsentEndpoint = chatbotRemoteConsent ? phratumaEndpoint : '';
    if (!chatbotRemoteConsent) {
      // EN: Clear remote advice immediately when consent is revoked. TH: ลบคำแนะนำจากระบบระยะไกลทันทีเมื่อถอนความยินยอม
      aiAdvice =
          ''; // EN: Remove the cached remote advice text. TH: ลบข้อความคำแนะนำระยะไกลที่ค้างอยู่
      aiAdviceCause =
          ''; // EN: Remove the associated remote cause text. TH: ลบสาเหตุจากระบบระยะไกลที่เกี่ยวข้อง
      aiAdviceDisclaimer =
          ''; // EN: Remove disclaimer metadata tied to that advice. TH: ลบ disclaimer ที่ผูกกับคำแนะนำเดิม
      _lastAdviceFor =
          ''; // EN: Allow a future eligible status to request new advice. TH: อนุญาตให้สถานะใหม่ที่ผ่านเงื่อนไขขอคำแนะนำได้
    }
    await _saveSettings();
    _notifyIfAlive();
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
    final previousEndpoint = phratumaEndpoint;
    phratumaEndpoint = endpoint?.trim() ?? phratumaEndpoint;
    if (phratumaEndpoint != previousEndpoint) {
      // A consent decision for one server must never authorize another server.
      chatbotRemoteConsent = false;
      chatbotRemoteConsentEndpoint = '';
      // EN: Clear advice from the previous destination when the endpoint changes. TH: ลบคำแนะนำจากปลายทางเดิมเมื่อเปลี่ยน endpoint
      aiAdvice =
          ''; // EN: Remove advice produced by the previous server. TH: ลบคำแนะนำจาก server เดิม
      aiAdviceCause =
          ''; // EN: Remove its associated cause. TH: ลบสาเหตุที่ผูกกับคำแนะนำเดิม
      aiAdviceDisclaimer =
          ''; // EN: Remove its associated disclaimer. TH: ลบ disclaimer ที่ผูกกับคำแนะนำเดิม
      _lastAdviceFor =
          ''; // EN: Reset the per-status request cache for the new endpoint. TH: ล้างสถานะคำขอเดิมก่อนใช้ endpoint ใหม่
    }
    modelName = model ?? modelName;
    cloudBaseUrl = cloudUrl ?? cloudBaseUrl;
    language = newLanguage ?? language;
    llmEnabled = enableLlm ?? llmEnabled;
    mockChatbotResponse = useMockChat ?? mockChatbotResponse;
    // Health-data sync stays hard-disabled until the backend validates the
    // authenticated account and enforces per-user authorization.
    cloudEnabled = false;
    cloudStatus =
        'Cloud sync disabled pending production privacy/security review';
    await _saveSettings();
    _notifyIfAlive();
  }

  Map<String, dynamic> get userProfile => {
        'userId': userId,
        'deviceId': deviceId,
        if (userName.trim().isNotEmpty &&
            userName != 'Doz user' &&
            userName != 'ผู้ใช้ doz')
          'name': userName,
        if (profileDetailsProvided) ...{
          'age': age,
          'birthDate': birthDate?.toIso8601String(),
          'weight': weight,
          'height': height,
          'gender': gender,
          'conditions': conditions,
          'emergencyContactName': emergencyContactName,
          'emergencyContactPhone': emergencyContactPhone,
        },
        if (latitude != null && longitude != null) ...{
          'latitude': latitude,
          'longitude': longitude,
        },
        'privacyPolicyAcceptedAt': privacyPolicyAcceptedAt?.toIso8601String(),
        'privacyPolicyVersion': privacyPolicyVersion,
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
    // EN: Export received optical ADC means and device time alongside derived metrics.
    // TH: ส่งออกค่าเฉลี่ย ADC แสงและเวลาอุปกรณ์ควบคู่กับค่าที่คำนวณแล้ว
    final buffer = StringBuffer();
    buffer.writeln(
      'timestamp,user_id,device_id,heart_rate,spo2,ecg_rate,ecg_rr_interval,ecg_hrv,gsr,temperature,accel_x,accel_y,accel_z,gyro_x,gyro_y,gyro_z,motion_magnitude,gyro_magnitude,risk_class,alert_level,red_adc_mean,ir_adc_mean,device_timestamp_ms',
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
        // EN: Empty cells mean no optical packet; means are not full waveforms.
        // TH: ช่องว่างหมายถึงไม่มี packet แสง และค่าเฉลี่ยไม่ใช่คลื่นสัญญาณเต็ม
        sensor.rawRed ?? '',
        sensor.rawIr ?? '',
        sensor.deviceTimestampMs ?? '',
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
    _notifyIfAlive();
    final ok = await _cloudService.uploadSensor(
      baseUrl: cloudBaseUrl,
      bearerToken: AuthService.currentAccessToken ?? '',
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
    _notifyIfAlive();
  }

  Future<void> _syncAlertToCloud(AlertRecord alert) async {
    if (!cloudEnabled ||
        cloudBaseUrl.trim().isEmpty ||
        _alertCloudSyncInFlight) {
      return;
    }
    _alertCloudSyncInFlight = true;
    cloudStatus = 'Syncing alert to cloud...';
    _notifyIfAlive();
    final ok = await _cloudService.uploadAlert(
      baseUrl: cloudBaseUrl,
      bearerToken: AuthService.currentAccessToken ?? '',
      alert: alert,
      userProfile: userProfile,
    );
    cloudStatus = ok ? 'Alert synced to cloud' : 'Cloud alert sync failed';
    _alertCloudSyncInFlight = false;
    _notifyIfAlive();
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
    _notifyIfAlive();
  }

  Future<void> _showAlertNotification(AlertRecord alert) async {
    final delivered = await _notificationService.showRiskAlert(
      riskResult: alert
          .riskResult, // EN: Pass only the status needed to set notification urgency. TH: ส่งเฉพาะสถานะที่ใช้กำหนดความเร่งด่วนของ notification
    );
    notificationStatus =
        delivered // EN: Report actual delivery instead of permission state alone. TH: รายงานผลการส่งจริงแทนการดูเฉพาะสถานะสิทธิ์
            ? 'Last notification sent' // EN: Show success only after the plugin accepted the request. TH: แสดงสำเร็จเมื่อ plugin รับคำขอแล้วเท่านั้น
            : 'Notification unavailable'; // EN: Use a neutral status for denial or platform failure. TH: ใช้สถานะกลางเมื่อถูกปฏิเสธหรือ platform ล้มเหลว
  }

  Future<bool> findDeviceForSetup() async {
    final cancelSignal = Completer<void>();
    _bleScanCancelSignal = cancelSignal;
    scannedBleDevices = const [];
    scanningBle = true;
    bleStatus = 'Scanning ESP32...';
    _notifyIfAlive();
    try {
      final results = await _bleService.scanForEsp32(
        cancelSignal: cancelSignal.future,
      );
      if (cancelSignal.isCompleted) {
        bleStatus = 'BLE scan cancelled';
        return false;
      }
      scannedBleDevices = List<ScanResult>.unmodifiable(results);
      final found = results.isNotEmpty;
      if (found) {
        bleDeviceName = _bleService.lastFoundDeviceName;
        bleDeviceId = _bleService.lastFoundDeviceId;
        bleStatus = 'Device found: $bleDeviceName';
      } else {
        bleStatus =
            'Doz device not found. Check power and BLE advertising; demo data is separate.';
      }
      return found;
    } catch (error) {
      bleStatus = cancelSignal.isCompleted
          ? 'BLE scan cancelled'
          : 'BLE scan failed: $error';
      return false;
    } finally {
      if (identical(_bleScanCancelSignal, cancelSignal)) {
        _bleScanCancelSignal = null;
      }
      scanningBle = false;
      _notifyIfAlive();
    }
  }

  Future<bool> scanForDevices() => findDeviceForSetup();

  Future<void> cancelBleScan() async {
    final cancelSignal = _bleScanCancelSignal;
    if (!scanningBle || cancelSignal == null) return;
    if (!cancelSignal.isCompleted) cancelSignal.complete();
    bleStatus = 'BLE scan cancelled';
    _notifyIfAlive();
    try {
      await _bleService.stopScan();
    } catch (_) {
      // The scan's own finally block also stops it; preserve the cancelled state.
    }
  }

  Future<bool> connectScannedDevice(ScanResult result) async {
    scanningBle = true;
    bleConnected = false;
    bleConnectedAt = null;
    _prepareForDeviceConnection();
    bleStatus = 'Connecting to ${result.device.platformName}...';
    _notifyIfAlive();
    try {
      await _bleService.connect(result.device);
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
      bleStatus = 'Connection failed: $error';
      return false;
    } finally {
      scanningBle = false;
      _notifyIfAlive();
    }
  }

  Future<bool> connectDeviceForSetup() async {
    scanningBle = true;
    bleConnected = false;
    bleConnectedAt = null;
    _prepareForDeviceConnection();
    bleStatus = 'Connecting ESP32...';
    _notifyIfAlive();
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
      _notifyIfAlive();
    }
  }

  Future<void> scanAndConnectBle() async {
    scanningBle = true;
    bleStatus = 'Scanning ESP32...';
    _notifyIfAlive();

    try {
      final results = await _bleService.scanForEsp32();
      if (results.isEmpty) {
        bleStatus =
            'Doz device not found. Demo data is separate from BLE connection.';
      } else {
        _prepareForDeviceConnection();
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
      _notifyIfAlive();
    }
  }

  Future<void> disconnectBle() async {
    await _bleService.disconnect();
    bleConnected = false;
    bleConnectedAt = null;
    bleStatus = 'Mock BLE stream connected';
    await _saveSettings();
    _notifyIfAlive();
  }

  void _prepareForDeviceConnection() {
    _warningTimer?.cancel();
    _warningTimer = null;
    _warningEpisodeAcknowledged = false;
    lastReadingWasFromDevice = false;
    lastSensorUpdateAt = null;
    _lastNotifiedFreshnessStatus = 'No sensor data yet';
    deviceBattery = null;
    sensorHistory.clear();
    sensorRiskHistory.clear();
    aiAdvice = '';
    aiAdviceCause = '';
    aiAdviceDisclaimer = '';
    _lastAdviceFor = '';
    currentSensor = SensorData(
      heartRate: 0,
      spo2: 0,
      gsr: 0,
      temperature: 0,
      accelX: 0,
      accelY: 0,
      accelZ: 0,
      gyroX: 0,
      gyroY: 0,
      gyroZ: 0,
    );
    currentRisk = const RiskResult(
      riskClass: 'AI analysis unavailable',
      alertLevel: 'Unknown',
      detectedSigns: ['Waiting for the first sensor packet.'],
      recommendation:
          'Connected device data has not arrived yet. No risk assessment is available.',
    );
    sensorStatus = 'Connected; waiting for first sensor packet';
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
    _notifyIfAlive();
  }

  Future<bool> updateLocation() async {
    final scope =
        authScopeId; // EN: Bind the request to the current account. TH: ผูกคำขอกับบัญชีปัจจุบัน
    if (!_isAuthScopeActive(scope)) {
      // EN: Require an active account before requesting location. TH: บังคับให้มีบัญชี active ก่อนขอตำแหน่ง
      return false; // EN: Refuse requests after sign-out or deletion. TH: ปฏิเสธคำขอหลัง sign-out หรือลบบัญชี
    } // EN: Continue for the active account. TH: ทำต่อเมื่อบัญชี active
    final requestEpoch =
        ++_locationRequestEpoch; // EN: Give this request a unique session generation. TH: กำหนด generation เฉพาะให้คำขอนี้
    requestingLocation = true;
    locationStatus = 'Requesting location...';
    _notifyIfAlive();

    try {
      final position = await _locationService.getCurrentPosition();
      if (!_isAuthScopeActive(scope) || requestEpoch != _locationRequestEpoch) {
        // EN: Discard results from an account/session that changed. TH: ทิ้งผลจากบัญชีหรือ session ที่เปลี่ยนไป
        return false; // EN: Do not apply stale coordinates. TH: ไม่ใช้พิกัดที่ล้าสมัย
      } // EN: Continue only for the request's original session. TH: ทำต่อเฉพาะ session เดิมของคำขอ
      latitude = position
          .latitude; // EN: Apply the verified latitude to the owning session. TH: ใช้ละติจูดกับ session เจ้าของคำขอ
      longitude = position
          .longitude; // EN: Apply the verified longitude to the owning session. TH: ใช้ลองจิจูดกับ session เจ้าของคำขอ
      locationStatus =
          'Location ready: ${latitude!.toStringAsFixed(5)}, ${longitude!.toStringAsFixed(5)}';
      await _saveSettings();
      return _isAuthScopeActive(scope) &&
          requestEpoch ==
              _locationRequestEpoch; // EN: Report success only if the same session still owns the result. TH: รายงานสำเร็จเมื่อ session เดิมยังเป็นเจ้าของผล
    } catch (_) {
      // EN: Avoid exposing platform exception contents to the UI. TH: ไม่เปิดเผยรายละเอียด exception ของระบบใน UI
      if (_isAuthScopeActive(scope) && requestEpoch == _locationRequestEpoch) {
        // EN: Update status only for the active request. TH: เปลี่ยนสถานะเฉพาะคำขอที่ยัง active
        locationStatus =
            'Location unavailable. Check permission and device settings.'; // EN: Show a generic message without exposing platform exception details. TH: แสดงข้อความทั่วไปโดยไม่เผยรายละเอียด exception ของระบบ
      } // EN: Leave a newer account's location status untouched. TH: ไม่แตะสถานะตำแหน่งของบัญชีใหม่
      return false;
    } finally {
      if (_isAuthScopeActive(scope) && requestEpoch == _locationRequestEpoch) {
        // EN: Clear progress only for this still-current request. TH: ล้างสถานะกำลังทำเฉพาะคำขอที่ยังเป็นปัจจุบัน
        requestingLocation =
            false; // EN: Finish this request's progress state. TH: จบสถานะกำลังทำของคำขอนี้
        _notifyIfAlive(); // EN: Refresh only the owning account's UI. TH: อัปเดต UI เฉพาะบัญชีเจ้าของคำขอ
      } // EN: Do not overwrite a newer session's progress state. TH: ไม่เขียนทับสถานะของ session ใหม่
    }
  }

  /// Remove the optional location from memory and this account's local store.
  Future<void> clearLocation() async {
    final scope =
        authScopeId; // EN: Capture the owner before mutating location state. TH: จับเจ้าของก่อนแก้ state ตำแหน่ง
    if (!_isAuthScopeActive(scope)) {
      // EN: Check the account before changing state. TH: ตรวจบัญชีก่อนเปลี่ยน state
      return; // EN: Ignore a clear request outside an active account. TH: ข้ามคำขอล้างเมื่อไม่มีบัญชี active
    } // EN: Continue for the active account. TH: ทำต่อกับบัญชีที่ active
    latitude = null;
    longitude = null;
    locationStatus = 'Location cleared';
    await _enqueueAccountStorageOperation(scope, () async {
      // EN: Serialize clearing with account save and deletion. TH: จัดลำดับการล้างร่วมกับ save และ delete ของบัญชี
      final prefs = await SharedPreferences
          .getInstance(); // EN: Open preferences for the captured account. TH: เปิด preferences ของบัญชีที่ snapshot
      if (!_isAuthScopeActive(scope)) {
        // EN: Check the session after opening preferences. TH: ตรวจ session หลังเปิด preferences
        return; // EN: Stop stale location cleanup. TH: หยุดการล้างตำแหน่งที่ล้าสมัย
      } // EN: Continue while the same account is active. TH: ทำต่อเมื่อบัญชีเดิมยัง active
      await prefs.remove(
          'doz.$scope.latitude'); // EN: Remove latitude only from the captured account. TH: ลบละติจูดเฉพาะบัญชีที่ snapshot
      if (!_isAuthScopeActive(scope)) {
        // EN: Recheck before removing longitude. TH: ตรวจซ้ำก่อนลบลองจิจูด
        return; // EN: Stop remaining writes after a session change. TH: หยุด write ที่เหลือเมื่อ session เปลี่ยน
      } // EN: Continue only for the same account. TH: ทำต่อเฉพาะบัญชีเดิม
      await prefs.remove(
          'doz.$scope.longitude'); // EN: Remove longitude only from the captured account. TH: ลบลองจิจูดเฉพาะบัญชีที่ snapshot
      if (!_isAuthScopeActive(scope)) {
        // EN: Check ownership before secure profile access. TH: ตรวจเจ้าของก่อนเข้าถึง secure profile
        return; // EN: Stop after an account switch. TH: หยุดหลังสลับบัญชี
      } // EN: Continue only for the captured account. TH: ทำต่อเฉพาะบัญชีที่ snapshot
      final profile = await _secureProfileStorage.readProfile(
          scope); // EN: Read the profile from the captured namespace. TH: อ่านโปรไฟล์จาก namespace ที่ snapshot
      if (!_isAuthScopeActive(scope)) {
        // EN: Recheck after the asynchronous secure read. TH: ตรวจซ้ำหลัง secure read แบบ async
        return; // EN: Do not modify a profile after sign-out. TH: ไม่แก้โปรไฟล์หลัง sign-out
      } // EN: Continue for the active account. TH: ทำต่อเมื่อบัญชียัง active
      profile
        ..remove('latitude')
        ..remove(
            'longitude'); // EN: Remove location fields from the captured profile. TH: ลบ field ตำแหน่งจากโปรไฟล์ที่ snapshot
      if (!_isAuthScopeActive(scope)) {
        // EN: Check ownership before persisting the profile. TH: ตรวจเจ้าของก่อนบันทึกโปรไฟล์
        return; // EN: Do not persist to an inactive account. TH: ไม่บันทึกลงบัญชีที่ไม่ active
      } // EN: Continue for the original account. TH: ทำต่อกับบัญชีเดิม
      await _secureProfileStorage.writeProfile(scope,
          profile); // EN: Save the modified profile to its original account. TH: บันทึกโปรไฟล์ที่แก้ลงบัญชีเดิม
    }); // EN: Finish the serialized location clear. TH: จบการล้างตำแหน่งที่จัดลำดับแล้ว
    if (_isAuthScopeActive(scope)) {
      // EN: Notify only the account whose location was cleared. TH: แจ้งเฉพาะบัญชีที่ล้างตำแหน่ง
      _notifyIfAlive(); // EN: Refresh the active account's UI. TH: อัปเดต UI ของบัญชีที่ active
    } // EN: Finish the account-scoped notification. TH: จบการแจ้งเตือนตามบัญชี
  }

  Future<void> _loadSettings(String? authUserId) async {
    final scope = authUserId ??
        'local-demo'; // EN: Capture the account scope before queuing initialization. TH: จับ scope บัญชีก่อนเข้าคิวเริ่มต้น
    await _enqueueAccountStorageOperation(
      // EN: Serialize profile migration/read with saves and deletion. TH: จัดลำดับ migration/read โปรไฟล์ร่วมกับ save และ delete
      scope, // EN: Use the captured scope as the queue key. TH: ใช้ scope ที่ snapshot เป็น key ของคิว
      () => _loadSettingsForScope(
          authUserId), // EN: Run the original loader only while this scope is active. TH: เรียก loader เดิมเมื่อ scope ยัง active เท่านั้น
    ); // EN: Finish the queued settings load. TH: จบการโหลด settings ที่เข้าคิว
  } // EN: Finish the serialized loader entry point. TH: จบ entry point ของ loader แบบจัดคิว

  Future<void> _loadSettingsForScope(String? authUserId) async {
    // EN: Load settings under the account storage queue. TH: โหลด settings ภายในคิว storage ของบัญชี
    final requestedScope = authUserId ??
        'local-demo'; // EN: Snapshot the intended account namespace. TH: เก็บ namespace ของบัญชีที่กำลังโหลด
    final prefs = await SharedPreferences
        .getInstance(); // EN: Open local preferences before reading scoped settings. TH: เปิด preferences ก่อนอ่านค่าตาม scope
    if (!_isAuthScopeActive(requestedScope)) {
      // EN: Stop stale initialization. TH: หยุดการเริ่มโหลดที่ล้าสมัย
      return; // EN: Abort after a sign-out or account switch. TH: หยุดเมื่อ sign-out หรือสลับบัญชี
    } // EN: Continue only for the active account. TH: ทำต่อเฉพาะบัญชีที่ active
    const configuredCloudBaseUrl =
        String.fromEnvironment('VITAGAURD_CLOUD_BASE_URL');
    final storedScope = prefs.getString('authScopeId');
    authScopeId = requestedScope;
    _alertStorage.setScope(requestedScope);
    await _migrateLegacyPreferences(prefs, requestedScope, storedScope);
    if (!_isAuthScopeActive(requestedScope)) {
      // EN: Check ownership after migration. TH: ตรวจเจ้าของหลัง migration
      return; // EN: Stop the old account migration. TH: หยุด migration ของบัญชีเดิม
    } // EN: Continue when the same account remains active. TH: ทำต่อเมื่อบัญชีเดิมยัง active
    await _secureProfileStorage.migrateLegacyPreferences(
      preferences: prefs,
      scope: requestedScope,
      removeUnscopedLegacy:
          requestedScope == 'local-demo' || storedScope == requestedScope,
    );
    if (!_isAuthScopeActive(requestedScope)) {
      // EN: Check ownership before profile access. TH: ตรวจเจ้าของก่อนอ่านโปรไฟล์
      return; // EN: Stop if this session ended. TH: หยุดหาก session จบแล้ว
    } // EN: Continue only for the active session. TH: ทำต่อเฉพาะ session ที่ active
    final secureProfile =
        await _secureProfileStorage.readProfile(requestedScope);
    if (!_isAuthScopeActive(requestedScope)) {
      // EN: Validate the session after profile read. TH: ตรวจ session หลังอ่านโปรไฟล์
      return; // EN: Never apply a stale profile to the current state. TH: ห้ามใช้โปรไฟล์เก่ากับ state ปัจจุบัน
    } // EN: Continue only when the profile still belongs to this session. TH: ทำต่อเมื่อโปรไฟล์ยังเป็นของ session นี้
    await prefs.setString('authScopeId', requestedScope);
    if (!_isAuthScopeActive(requestedScope)) {
      // EN: Recheck before applying stored values. TH: ตรวจซ้ำก่อนนำค่าที่บันทึกไว้มาใช้
      return; // EN: Do not hydrate state for a stale account. TH: ไม่เติม state ให้บัญชีที่ไม่ active แล้ว
    } // EN: Continue with state hydration for the active account. TH: เติม state ให้บัญชีที่ active ต่อไป
    setupDone = prefs.getBool(_scopedKey('setupDone')) ?? false;
    final storedPolicyVersion =
        prefs.getString(_scopedKey('privacyPolicyVersion'));
    if (storedPolicyVersion != privacyPolicyVersion) {
      // Require the user to review the materially revised prototype notice.
      setupDone = false;
      privacyPolicyAcceptedAt = null;
      await prefs.remove(_scopedKey('privacyPolicyAcceptedAt'));
      if (!_isAuthScopeActive(requestedScope)) {
        // EN: Stop after policy cleanup if the session changed. TH: หยุดหลังล้างข้อมูลนโยบายหาก session เปลี่ยน
        return; // EN: Do not apply old-account settings. TH: ไม่ใช้ค่าตั้งของบัญชีเดิมต่อ
      } // EN: Continue only for the same active account. TH: ทำต่อเมื่อบัญชีเดิมยัง active
      if (secureProfile.remove('privacyPolicyAcceptedAt') != null) {
        await _secureProfileStorage.writeProfile(
          requestedScope,
          secureProfile,
        );
        if (!_isAuthScopeActive(requestedScope)) {
          // EN: Recheck after the secure profile write. TH: ตรวจซ้ำหลังเขียนโปรไฟล์ปลอดภัย
          return; // EN: Do not continue stale account hydration. TH: ไม่เติมข้อมูลบัญชีเก่าต่อ
        } // EN: Continue only for the active account. TH: ทำต่อเฉพาะบัญชีที่ active
      }
    }
    userId = authUserId ?? (prefs.getString(_scopedKey('userId')) ?? userId);
    if (userId.isEmpty) {
      userId = 'user-${DateTime.now().microsecondsSinceEpoch}';
      await prefs.setString(_scopedKey('userId'), userId);
      if (!_isAuthScopeActive(requestedScope)) {
        // EN: Recheck after creating a local user ID. TH: ตรวจซ้ำหลังสร้างรหัสผู้ใช้ในเครื่อง
        return; // EN: Stop stale hydration. TH: หยุดเติมข้อมูลที่ล้าสมัย
      } // EN: Continue for the original session. TH: ทำต่อใน session เดิม
    }
    deviceId = prefs.getString(_scopedKey('deviceId')) ?? deviceId;
    if (deviceId.isEmpty) {
      deviceId = 'device-${DateTime.now().microsecondsSinceEpoch}';
      await prefs.setString(_scopedKey('deviceId'), deviceId);
      if (!_isAuthScopeActive(requestedScope)) {
        // EN: Recheck after creating a local device ID. TH: ตรวจซ้ำหลังสร้างรหัสอุปกรณ์ในเครื่อง
        return; // EN: Stop stale hydration. TH: หยุดเติมข้อมูลที่ล้าสมัย
      } // EN: Continue for the original session. TH: ทำต่อใน session เดิม
    }
    phratumaEndpoint =
        prefs.getString(_scopedKey('phratumaEndpoint')) ?? phratumaEndpoint;
    cloudBaseUrl = configuredCloudBaseUrl.isNotEmpty
        ? configuredCloudBaseUrl
        : (prefs.getString(_scopedKey('cloudBaseUrl')) ?? cloudBaseUrl);
    // ถ้าตั้ง base URL ผ่าน --dart-define ให้ chatbot ใช้ /chat ของ server เดียวกัน
    // (กันกรณีค้าง placeholder example.com แล้ว chatbot ตอบ fallback เดิมทุกครั้ง)
    if (configuredCloudBaseUrl.isNotEmpty) {
      final base = configuredCloudBaseUrl.replaceAll(RegExp(r'/+$'), '');
      phratumaEndpoint = '$base/chat';
    }
    modelName = prefs.getString(_scopedKey('modelName')) ?? modelName;
    language = prefs.getString(_scopedKey('language')) ?? language;
    _resetChatToWelcome();
    llmEnabled = prefs.getBool(_scopedKey('llmEnabled')) ?? llmEnabled;
    chatbotRemoteConsent =
        prefs.getBool(_scopedKey('chatbotRemoteConsent')) ?? false;
    chatbotRemoteConsentEndpoint =
        prefs.getString(_scopedKey('chatbotRemoteConsentEndpoint')) ?? '';
    if (chatbotRemoteConsentEndpoint != phratumaEndpoint) {
      chatbotRemoteConsent = false;
      chatbotRemoteConsentEndpoint = '';
    }
    mockChatbotResponse =
        prefs.getBool(_scopedKey('mockChatbotResponse')) ?? mockChatbotResponse;
    // A configured server is not itself user consent to transmit health data.
    cloudEnabled = false;
    cloudStatus =
        'Cloud sync disabled pending production privacy/security review';
    bleDeviceName =
        prefs.getString(_scopedKey('bleDeviceName')) ?? bleDeviceName;
    bleDeviceId = prefs.getString(_scopedKey('bleDeviceId')) ?? bleDeviceId;
    bleServiceUuid =
        prefs.getString(_scopedKey('bleServiceUuid')) ?? bleServiceUuid;
    bleCharacteristicUuid =
        prefs.getString(_scopedKey('bleCharacteristicUuid')) ??
            bleCharacteristicUuid;
    final connectedAtRaw = prefs.getString(_scopedKey('bleConnectedAt'));
    bleConnectedAt =
        connectedAtRaw == null ? null : DateTime.tryParse(connectedAtRaw);
    final lastSensorAtRaw = prefs.getString(_scopedKey('lastSensorUpdateAt'));
    lastSensorUpdateAt =
        lastSensorAtRaw == null ? null : DateTime.tryParse(lastSensorAtRaw);
    sensorStatus = prefs.getString(_scopedKey('sensorStatus')) ?? sensorStatus;
    userName = secureProfile['userName'] is String
        ? secureProfile['userName'] as String
        : userName;
    emergencyContactName = secureProfile['emergencyContactName'] is String
        ? secureProfile['emergencyContactName'] as String
        : emergencyContactName;
    emergencyContactPhone = secureProfile['emergencyContactPhone'] is String
        ? secureProfile['emergencyContactPhone'] as String
        : emergencyContactPhone;
    final acceptedAtRaw = secureProfile['privacyPolicyAcceptedAt']?.toString();
    privacyPolicyAcceptedAt =
        acceptedAtRaw == null ? null : DateTime.tryParse(acceptedAtRaw);
    final secureWeight = _finiteProfileNumber(secureProfile['weight']);
    final secureHeight = _finiteProfileNumber(secureProfile['height']);
    final secureAge = secureProfile['age'];
    if (secureWeight != null) weight = secureWeight;
    if (secureHeight != null) height = secureHeight;
    if (secureAge is int && secureAge >= 0 && secureAge <= 130) age = secureAge;
    final birthDateRaw = secureProfile['birthDate']?.toString();
    birthDate = birthDateRaw == null ? null : DateTime.tryParse(birthDateRaw);
    profileDetailsProvided = secureProfile['profileDetailsProvided'] is bool
        ? secureProfile['profileDetailsProvided'] as bool
        : (secureWeight != null ||
            secureHeight != null ||
            birthDateRaw != null);
    gender = secureProfile['gender'] is String
        ? secureProfile['gender'] as String
        : gender;
    conditions = secureProfile['conditions'] is String
        ? secureProfile['conditions'] as String
        : conditions;
    final storedLatitude = _finiteProfileNumber(secureProfile['latitude']);
    final storedLongitude = _finiteProfileNumber(secureProfile['longitude']);
    latitude =
        storedLatitude != null && storedLatitude >= -90 && storedLatitude <= 90
            ? storedLatitude
            : null;
    longitude = storedLongitude != null &&
            storedLongitude >= -180 &&
            storedLongitude <= 180
        ? storedLongitude
        : null;
    if (latitude != null && longitude != null) {
      locationStatus =
          'Location ready: ${latitude!.toStringAsFixed(5)}, ${longitude!.toStringAsFixed(5)}';
    }
  }

  Future<void> _saveSettings() async {
    final scope =
        authScopeId; // EN: Snapshot the owner before any asynchronous storage work. TH: เก็บ scope เจ้าของก่อนเริ่ม storage แบบ async
    if (!_isAuthScopeActive(scope)) {
      // EN: Verify the captured owner before saving. TH: ตรวจเจ้าของที่ snapshot ก่อนบันทึก
      return; // EN: Do not persist after the account session has ended. TH: ไม่บันทึกหลัง session บัญชีจบ
    } // EN: Continue only while the captured account remains active. TH: ทำต่อเมื่อบัญชีที่ snapshot ยัง active
    final settings = <String, Object?>{
      // EN: Snapshot mutable settings before the first await. TH: snapshot ค่าตั้งที่เปลี่ยนได้ก่อน await แรก
      'setupDone':
          setupDone, // EN: Preserve setup completion. TH: เก็บสถานะการตั้งค่าเริ่มต้น
      'privacyPolicyVersion':
          privacyPolicyVersion, // EN: Preserve the accepted policy version. TH: เก็บเวอร์ชันนโยบายที่ยอมรับ
      'userId':
          userId, // EN: Preserve the app user identifier. TH: เก็บรหัสผู้ใช้ของแอป
      'deviceId':
          deviceId, // EN: Preserve the device identifier. TH: เก็บรหัสอุปกรณ์
      'phratumaEndpoint':
          phratumaEndpoint, // EN: Preserve the configured chatbot endpoint. TH: เก็บ endpoint ของ chatbot
      'cloudBaseUrl':
          cloudBaseUrl, // EN: Preserve the cloud API base URL. TH: เก็บ URL หลักของ cloud API
      'modelName':
          modelName, // EN: Preserve the selected AI model name. TH: เก็บชื่อโมเดล AI ที่เลือก
      'language':
          language, // EN: Preserve the selected language. TH: เก็บภาษาที่เลือก
      'llmEnabled':
          llmEnabled, // EN: Preserve the LLM feature toggle. TH: เก็บสวิตช์เปิดใช้ LLM
      'chatbotRemoteConsent':
          chatbotRemoteConsent, // EN: Preserve explicit remote-chat consent. TH: เก็บความยินยอมใช้ chatbot ระยะไกล
      'chatbotRemoteConsentEndpoint':
          chatbotRemoteConsentEndpoint, // EN: Bind consent to its endpoint. TH: ผูกความยินยอมกับ endpoint ที่ระบุ
      'mockChatbotResponse':
          mockChatbotResponse, // EN: Preserve the chatbot preview setting. TH: เก็บค่าตั้ง preview chatbot
      'cloudEnabled':
          cloudEnabled, // EN: Preserve the cloud-sync setting. TH: เก็บค่าตั้ง cloud sync
      'bleDeviceName':
          bleDeviceName, // EN: Preserve the BLE display name. TH: เก็บชื่อแสดง BLE
      'bleDeviceId':
          bleDeviceId, // EN: Preserve the BLE device identifier. TH: เก็บรหัส BLE device
      'bleServiceUuid':
          bleServiceUuid, // EN: Preserve the BLE service UUID. TH: เก็บ service UUID ของ BLE
      'bleCharacteristicUuid':
          bleCharacteristicUuid, // EN: Preserve the BLE characteristic UUID. TH: เก็บ characteristic UUID ของ BLE
      'bleConnectedAt': bleConnectedAt
          ?.toIso8601String(), // EN: Snapshot the BLE connection time or its absence. TH: เก็บเวลาต่อ BLE หรือ null
      'lastSensorUpdateAt': lastSensorUpdateAt
          ?.toIso8601String(), // EN: Snapshot the latest sensor timestamp or its absence. TH: เก็บเวลา sensor ล่าสุดหรือ null
      'sensorStatus':
          sensorStatus, // EN: Preserve the current sensor status text. TH: เก็บข้อความสถานะ sensor
    }; // EN: Finish the immutable-in-practice settings snapshot. TH: จบ snapshot ค่าตั้ง
    final secureProfile = <String, Object?>{
      // EN: Snapshot sensitive fields for the account-scoped secure store. TH: snapshot ข้อมูลอ่อนไหวสำหรับ secure storage ของบัญชี
      'userName':
          userName, // EN: Preserve the profile name. TH: เก็บชื่อโปรไฟล์
      'emergencyContactName':
          emergencyContactName, // EN: Preserve the emergency contact name. TH: เก็บชื่อผู้ติดต่อฉุกเฉิน
      'emergencyContactPhone':
          emergencyContactPhone, // EN: Preserve the emergency contact number. TH: เก็บเบอร์ผู้ติดต่อฉุกเฉิน
      'weight':
          weight, // EN: Preserve the profile weight. TH: เก็บน้ำหนักในโปรไฟล์
      'height':
          height, // EN: Preserve the profile height. TH: เก็บส่วนสูงในโปรไฟล์
      'age': age, // EN: Preserve the profile age. TH: เก็บอายุในโปรไฟล์
      'profileDetailsProvided':
          profileDetailsProvided, // EN: Preserve profile-completion state. TH: เก็บสถานะกรอกรายละเอียดโปรไฟล์
      'birthDate': birthDate
          ?.toIso8601String(), // EN: Snapshot the birth date or its absence. TH: เก็บวันเกิดหรือ null
      'gender':
          gender, // EN: Preserve the selected gender value. TH: เก็บค่าเพศที่เลือก
      'conditions':
          conditions, // EN: Preserve the user-entered conditions. TH: เก็บข้อมูลภาวะสุขภาพที่ผู้ใช้กรอก
      'privacyPolicyAcceptedAt': privacyPolicyAcceptedAt
          ?.toIso8601String(), // EN: Snapshot policy acceptance time or its absence. TH: เก็บเวลายอมรับนโยบายหรือ null
      'latitude':
          latitude, // EN: Preserve the optional latitude. TH: เก็บละติจูดแบบ optional
      'longitude':
          longitude, // EN: Preserve the optional longitude. TH: เก็บลองจิจูดแบบ optional
    }; // EN: Finish the secure-profile snapshot. TH: จบ snapshot โปรไฟล์ที่ต้องเก็บอย่างปลอดภัย
    final prefs = await SharedPreferences
        .getInstance(); // EN: Open preferences for the active account. TH: เปิด preferences สำหรับบัญชีที่ active
    if (!_isAuthScopeActive(scope)) {
      // EN: Check whether the session changed during initialization. TH: ตรวจว่า session เปลี่ยนระหว่างเตรียม preferences หรือไม่
      return; // EN: Abort this stale save operation. TH: หยุดการบันทึกที่ล้าสมัย
    } // EN: Continue only for the same active scope. TH: ทำต่อเฉพาะ scope เดิมที่ยัง active
    await _enqueueAccountStorageOperation(scope, () async {
      // EN: Serialize writes so account deletion can wait for them. TH: จัดลำดับ write เพื่อให้ขั้นตอนลบบัญชีรอได้
      for (final entry in settings.entries) {
        // EN: Persist each captured preference under the captured scope. TH: บันทึก preference ที่ snapshot ไว้ภายใต้ scope เดิม
        if (!_isAuthScopeActive(scope)) {
          // EN: Recheck before each individual preference write. TH: ตรวจซ้ำก่อนเขียน preference แต่ละรายการ
          return; // EN: Stop remaining writes on sign-out, deletion, or account switch. TH: หยุด write ที่เหลือเมื่อ sign-out ลบบัญชี หรือสลับบัญชี
        } // EN: Continue while the original account remains active. TH: ทำต่อเมื่อบัญชีเดิมยัง active
        final key =
            'doz.$scope.${entry.key}'; // EN: Keep the key bound to the captured account. TH: ผูก key ไว้กับบัญชีที่ snapshot
        final value = entry
            .value; // EN: Read only the captured value. TH: อ่านเฉพาะค่าที่ snapshot
        if (value == null) {
          // EN: Remove optional values that were cleared. TH: ลบค่าที่เป็น optional และถูกล้าง
          await prefs.remove(
              key); // EN: Remove the captured account's stale value. TH: ลบค่าเก่าของบัญชีที่ snapshot
        } else if (value is bool) {
          // EN: Handle boolean preferences. TH: จัดการ preference ชนิด boolean
          await prefs.setBool(
              key, value); // EN: Store the boolean value. TH: บันทึกค่า boolean
        } else if (value is int) {
          // EN: Handle integer preferences. TH: จัดการ preference ชนิดจำนวนเต็ม
          await prefs.setInt(key,
              value); // EN: Store the integer value. TH: บันทึกค่าจำนวนเต็ม
        } else if (value is double) {
          // EN: Handle decimal preferences. TH: จัดการ preference ชนิดทศนิยม
          await prefs.setDouble(
              key, value); // EN: Store the decimal value. TH: บันทึกค่าทศนิยม
        } else if (value is String) {
          // EN: Handle text preferences. TH: จัดการ preference ชนิดข้อความ
          await prefs.setString(
              key, value); // EN: Store the string value. TH: บันทึกข้อความ
        } else {
          // EN: Reject unsupported setting types explicitly. TH: ปฏิเสธชนิดค่าตั้งที่ยังไม่รองรับอย่างชัดเจน
          throw StateError(
              'Unsupported setting type for ${entry.key}.'); // EN: Surface a coding error instead of silently losing data. TH: แจ้งข้อผิดพลาดในโค้ดแทนการทิ้งข้อมูลเงียบๆ
        } // EN: Finish this setting operation. TH: จบการจัดการค่าตั้งนี้
      } // EN: Finish the ordered preferences. TH: จบการบันทึก preferences ตามลำดับ
      if (!_isAuthScopeActive(scope)) {
        // EN: Recheck ownership before secure profile storage. TH: ตรวจเจ้าของก่อนเขียนโปรไฟล์ปลอดภัย
        return; // EN: Do not persist the profile after session invalidation. TH: ไม่บันทึกโปรไฟล์หลัง session ถูกยกเลิก
      } // EN: Continue for the captured active account. TH: ทำต่อสำหรับบัญชีที่ snapshot และยัง active
      await _secureProfileStorage.writeProfile(scope,
          secureProfile); // EN: Persist only the captured profile to the original account. TH: บันทึกเฉพาะโปรไฟล์ snapshot ลงบัญชีเดิม
    }); // EN: Complete the serialized account-scoped save. TH: จบการบันทึกตาม scope แบบจัดลำดับ
  }

  Future<void> _enqueueAccountStorageOperation(
    // EN: Serialize storage operations independently per account. TH: จัดลำดับงาน storage แยกตามบัญชี
    String
        scope, // EN: Identify the local account namespace. TH: ระบุ namespace ของบัญชีในเครื่อง
    Future<void> Function()
        write, // EN: Receive the bounded operation to serialize. TH: รับงานบันทึกที่ต้องจัดลำดับ
  ) async {
    // EN: Return when this account's operation finishes. TH: คืนค่าเมื่อ operation ของบัญชีนี้เสร็จ
    final previous = _accountStorageQueues[scope] ??
        Future<
            void>.value(); // EN: Chain after the last known account operation. TH: ต่อคิวหลัง operation ล่าสุดของบัญชี
    final next = previous.catchError((Object _) {}).then((_) async {
      // EN: Allow the queue to recover after a previous write failure. TH: ให้คิวทำงานต่อได้หลัง write ก่อนหน้าล้มเหลว
      if (!_isAuthScopeActive(scope)) {
        // EN: Recheck the account before starting queued work. TH: ตรวจบัญชีก่อนเริ่มงานที่อยู่ในคิว
        return; // EN: Skip writes for signed-out or deleted accounts. TH: ข้าม write ของบัญชีที่ sign-out หรือลบแล้ว
      } // EN: Continue while this scope is active. TH: ทำต่อเมื่อ scope นี้ active
      await write(); // EN: Run exactly one serialized account write operation. TH: ทำงานเขียนของบัญชีทีละ operation
    }); // EN: Build the future representing this queued operation. TH: สร้าง future แทนงานที่เข้าคิวนี้
    _accountStorageQueues[scope] =
        next; // EN: Publish the pending operation so deletion can await it. TH: บันทึก future ที่ค้างไว้เพื่อให้ deletion รอได้
    try {
      // EN: Preserve the operation result for its caller. TH: ส่งผล operation กลับให้ caller
      await next; // EN: Wait for all writes in this operation. TH: รอ write ทั้งหมดใน operation นี้
    } finally {
      // EN: Remove only the queue entry that is still current. TH: ลบเฉพาะ queue entry ที่ยังเป็นรายการปัจจุบัน
      if (identical(_accountStorageQueues[scope], next)) {
        // EN: Avoid erasing a newer queued operation. TH: ป้องกันลบ operation ใหม่ที่เข้าคิวตามมา
        _accountStorageQueues.remove(
            scope); // EN: Release the account queue slot. TH: คืนช่องคิวของบัญชี
      } // EN: Finish the current-operation identity check. TH: จบการตรวจ identity ของ operation
    } // EN: Finish queue cleanup even after failures. TH: จบการล้างคิวแม้ operation ล้มเหลว
  } // EN: Finish the serialized settings-write helper. TH: จบ helper จัดลำดับการเขียน settings

  String _scopedKey(String key) =>
      'doz.$authScopeId.$key'; // EN: Build a local key using the currently bound account. TH: สร้าง key ในเครื่องตามบัญชีที่ผูกอยู่

  bool _isAuthScopeActive(String scope) {
    // EN: Fence asynchronous account work against sign-out and account changes. TH: กั้นงาน async ของบัญชีเมื่อ sign-out หรือเปลี่ยนบัญชี
    if (_disposed) return false;
    if (_invalidatedAccountScopes.contains(scope)) {
      // EN: Reject writes for accounts whose deletion already succeeded. TH: ปฏิเสธ write ของบัญชีที่ลบสำเร็จแล้ว
      return false; // EN: Keep deleted account data from being recreated locally. TH: ป้องกันสร้างข้อมูลบัญชีที่ลบแล้วกลับมาในเครื่อง
    } // EN: Continue checking runtime and provider session state. TH: ตรวจสถานะ session runtime และ provider ต่อ
    if (!_authSessionActive) {
      // EN: Check the runtime session fence. TH: ตรวจตัวกั้น session runtime
      return false; // EN: Reject account work after sign-out cleanup. TH: ปฏิเสธงานบัญชีหลังล้างข้อมูล sign-out
    } // EN: Continue to check the configured identity. TH: ตรวจ identity ต่อ
    if (!AuthService.isConfigured) {
      // EN: Handle builds without an auth provider. TH: จัดการ build ที่ไม่ได้ตั้ง auth provider
      return scope == 'local-demo' ||
          _allowUnconfiguredTestScopes; // EN: Permit demo scope, plus explicit test scopes. TH: อนุญาต demo และ scope ทดสอบที่ระบุชัดเจน
    } // EN: Continue to validate the provider identity. TH: ตรวจ identity จาก provider ต่อ
    return AuthService.currentUserId ==
        scope; // EN: Require the provider's current identity to match the scope. TH: บังคับให้ identity ปัจจุบันตรงกับ scope
  } // EN: Finish the active-scope guard. TH: จบตัวตรวจ scope ที่ active

  Future<void> _migrateLegacyPreferences(
    SharedPreferences prefs,
    String requestedScope,
    String? storedScope,
  ) async {
    const legacyKeys = <String>[
      'setupDone',
      'privacyPolicyVersion',
      'userId',
      'deviceId',
      'phratumaEndpoint',
      'cloudBaseUrl',
      'modelName',
      'language',
      'llmEnabled',
      'chatbotRemoteConsent',
      'chatbotRemoteConsentEndpoint',
      'mockChatbotResponse',
      'cloudEnabled',
      'bleDeviceName',
      'bleDeviceId',
      'bleServiceUuid',
      'bleCharacteristicUuid',
      'bleConnectedAt',
      'lastSensorUpdateAt',
      'sensorStatus',
      'userName',
      'emergencyContactName',
      'emergencyContactPhone',
      'weight',
      'height',
      'age',
      'profileDetailsProvided',
      'birthDate',
      'gender',
      'conditions',
      'privacyPolicyAcceptedAt',
      'latitude',
      'longitude',
    ];
    if ((storedScope != null && storedScope != requestedScope) ||
        (requestedScope != 'local-demo' && storedScope == null)) {
      return;
    }
    for (final key in legacyKeys) {
      final scopedKey = 'doz.$requestedScope.$key';
      if (prefs.containsKey(scopedKey) || !prefs.containsKey(key)) continue;
      final value = prefs.get(key);
      if (value is String) await prefs.setString(scopedKey, value);
      if (value is bool) await prefs.setBool(scopedKey, value);
      if (value is int) await prefs.setInt(scopedKey, value);
      if (value is double) await prefs.setDouble(scopedKey, value);
    }
    await _alertStorage.migrateLegacyHistoryIfNeeded(scopeId: requestedScope);
  }

  // EN: Ignore late UI notifications from asynchronous work after disposal.
  // TH: ข้ามการแจ้ง UI ที่มาช้าจากงาน async หลัง dispose
  void _notifyIfAlive() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _warningTimer?.cancel();
    _bleSubscription?.cancel();
    _bleDisconnectSubscription?.cancel();
    _authSubscription?.cancel();
    _bleService.dispose();
    _phratumaService.dispose();
    _cloudService.dispose();
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

// EN: Reject nonnumeric and nonfinite values when reading the encrypted profile.
// TH: ปฏิเสธค่าที่ไม่ใช่ตัวเลขหรือไม่ finite ขณะอ่านโปรไฟล์ที่เข้ารหัส
double? _finiteProfileNumber(Object? value) {
  if (value is! num) return null;
  final number = value.toDouble();
  return number.isFinite ? number : null;
}
