import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/risk_result.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _permissionGranted = false;

  bool get initialized => _initialized;
  bool get permissionGranted => _permissionGranted;

  Future<bool> initialize() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    _initialized = await _plugin.initialize(settings: settings) ?? false;
    _permissionGranted = await requestPermission();
    return _initialized && _permissionGranted;
  }

  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final androidGranted = await android?.requestNotificationsPermission();

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final iosGranted = await ios?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );

    final macOS = _plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    final macOSGranted = await macOS?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );

    _permissionGranted = androidGranted ?? iosGranted ?? macOSGranted ?? true;
    return _permissionGranted;
  }

  Future<void> showRiskAlert({
    required RiskResult riskResult,
    required int heartRate,
    required int spo2,
  }) async {
    if (!_initialized) {
      await initialize();
    }
    if (!_permissionGranted) return;

    final isEmergency = riskResult.alertLevel == 'Emergency';
    final title =
        isEmergency ? 'Emergency health alert' : 'Health warning detected';
    final body =
        '${riskResult.riskClass}: HR $heartRate BPM, SpO2 $spo2%. ${riskResult.recommendation}';

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'dzoz_health_alerts',
        'Health alerts',
        channelDescription: 'Risk detection alerts from Dzoz',
        importance: isEmergency ? Importance.max : Importance.high,
        priority: isEmergency ? Priority.max : Priority.high,
        category: AndroidNotificationCategory.alarm,
        playSound: true,
        enableVibration: true,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
      macOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: title,
      body: body,
      notificationDetails: details,
      payload: riskResult.riskClass,
    );
  }
}
