import 'package:doz/services/secure_local_storage.dart';

/// EN: Test-only encrypted-store substitute; never wired into app runtime.
/// TH: ตัวแทน secure storage สำหรับ test เท่านั้น ไม่ถูกใช้ใน runtime ของแอป
class InMemorySecureKeyValueStore implements SecureKeyValueStore {
  InMemorySecureKeyValueStore([Map<String, String>? initialValues])
      : values = Map<String, String>.of(initialValues ?? const {});

  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
