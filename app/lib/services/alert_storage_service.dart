import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/alert_record.dart';

class AlertStorageService {
  static const _key = 'doz_alert_history';

  Future<List<AlertRecord>> loadAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => AlertRecord.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveAlerts(List<AlertRecord> alerts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(alerts.map((alert) => alert.toJson()).toList()),
    );
  }

  Future<void> clearAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
