import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/in_memory_secure_storage.dart';
import 'package:doz/services/secure_local_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('migrates profile into secure storage before deleting plaintext',
      () async {
    SharedPreferences.setMockInitialValues({
      'doz.account-a.weight': 58.5,
      'doz.account-a.conditions': 'None',
      'weight': 61.0,
      'doz.account-b.weight': 72.0,
    });
    final preferences = await SharedPreferences.getInstance();
    final secureStore = InMemorySecureKeyValueStore();
    final service = SecureProfileStorage(store: secureStore);

    await service.migrateLegacyPreferences(
      preferences: preferences,
      scope: 'account-a',
      removeUnscopedLegacy: true,
    );

    expect(await service.readProfile('account-a'), {
      'weight': 58.5,
      'conditions': 'None',
    });
    expect(preferences.containsKey('doz.account-a.weight'), isFalse);
    expect(preferences.containsKey('doz.account-a.conditions'), isFalse);
    expect(preferences.containsKey('weight'), isFalse);
    expect(preferences.getDouble('doz.account-b.weight'), 72.0);
  });

  test('preserves plaintext if existing secure data cannot be decoded',
      () async {
    SharedPreferences.setMockInitialValues({'doz.local-demo.weight': 64.0});
    final preferences = await SharedPreferences.getInstance();
    final service = SecureProfileStorage(
      store: InMemorySecureKeyValueStore(
        {'doz.local-demo.secure_profile.v1': 'not-json'},
      ),
    );

    await service.migrateLegacyPreferences(
      preferences: preferences,
      scope: 'local-demo',
    );

    expect(preferences.getDouble('doz.local-demo.weight'), 64.0);
    expect(preferences.getDouble('weight'), isNull);
  });

  test('merges unscoped legacy fields into secure data before cleanup',
      () async {
    SharedPreferences.setMockInitialValues({
      'doz.local-demo.userName': 'Scoped name',
      'emergencyContactPhone': '0812345678',
    });
    final preferences = await SharedPreferences.getInstance();
    final service = SecureProfileStorage(
      store: InMemorySecureKeyValueStore({
        'doz.local-demo.secure_profile.v1': '{"weight":62}',
      }),
    );

    await service.migrateLegacyPreferences(
      preferences: preferences,
      scope: 'local-demo',
      removeUnscopedLegacy: true,
    );

    expect(await service.readProfile('local-demo'), {
      'weight': 62,
      'userName': 'Scoped name',
      'emergencyContactPhone': '0812345678',
    });
    expect(preferences.containsKey('doz.local-demo.userName'), isFalse);
    expect(preferences.containsKey('emergencyContactPhone'), isFalse);
  });

  test('clearProfile deletes only the requested account profile', () async {
    final store = InMemorySecureKeyValueStore({
      'doz.account-a.secure_profile.v1': '{"weight":55}',
      'doz.account-b.secure_profile.v1': '{"weight":70}',
    });
    final service = SecureProfileStorage(store: store);

    await service.clearProfile('account-a');

    expect(await service.readProfile('account-a'), isEmpty);
    expect((await service.readProfile('account-b'))['weight'], 70);
  });
}
