import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest declares scoped BLE permissions', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(manifest, contains('android.permission.BLUETOOTH_SCAN'));
    expect(
        manifest, contains('android:usesPermissionFlags="neverForLocation"'));
    expect(manifest, contains('android.permission.BLUETOOTH_CONNECT'));
    expect(
      manifest,
      contains(
          'android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"'),
    );
    expect(
      manifest,
      contains(
          'android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"'),
    );
    expect(
      manifest,
      contains(
          'android:name="android.hardware.bluetooth_le" android:required="false"'),
    );
  });

  test('iOS declares Bluetooth usage descriptions and Thai localizations', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final thaiStrings =
        File('ios/Runner/th.lproj/InfoPlist.strings').readAsStringSync();
    final englishStrings =
        File('ios/Runner/en.lproj/InfoPlist.strings').readAsStringSync();
    final project =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();

    expect(plist, contains('<key>NSBluetoothAlwaysUsageDescription</key>'));
    expect(plist, contains('<key>NSBluetoothPeripheralUsageDescription</key>'));
    expect(thaiStrings, contains('NSBluetoothAlwaysUsageDescription'));
    expect(thaiStrings, contains('ไม่ใช้ Bluetooth เพื่อติดตามตำแหน่ง'));
    expect(englishStrings, contains('NSBluetoothAlwaysUsageDescription'));
    expect(englishStrings, contains('not used to track your location'));
    expect(project, contains('en.lproj/InfoPlist.strings'));
    expect(project, contains('th.lproj/InfoPlist.strings'));
    expect(project, contains('InfoPlist.strings in Resources'));
  });

  test('iOS plugin dependencies use Swift Package Manager, not CocoaPods', () {
    final project =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final workspace = File('ios/Runner.xcworkspace/contents.xcworkspacedata')
        .readAsStringSync();
    final debugConfig = File('ios/Flutter/Debug.xcconfig').readAsStringSync();
    final releaseConfig =
        File('ios/Flutter/Release.xcconfig').readAsStringSync();

    expect(project, contains('FlutterGeneratedPluginSwiftPackage'));
    expect(workspace, isNot(contains('Pods/Pods.xcodeproj')));
    expect(debugConfig, contains('Generated.xcconfig'));
    expect(releaseConfig, contains('Generated.xcconfig'));
    expect(debugConfig, isNot(contains('Pods/Target Support Files')));
    expect(releaseConfig, isNot(contains('Pods/Target Support Files')));
    expect(File('ios/Podfile').existsSync(), isFalse);
  });
}
