import 'dart:io';

import 'package:doz/legal/privacy_policy_draft.dart';
import 'package:doz/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepted policy version matches the current draft in both languages',
      () {
    final state = DozState();
    expect(state.privacyPolicyVersion, 'DRAFT-1.2');
    expect(privacyPolicyTextTh, contains('ฉบับร่าง 1.2'));
    expect(privacyPolicyTextEn, contains('Draft 1.2'));
    expect(privacyPolicyTextTh, contains('ข้อความสนทนาใน chatbot'));
    expect(privacyPolicyTextEn, contains('Chatbot conversation messages'));
    expect(privacyPolicyTextTh, contains('แอปไม่อ่านหรือส่งพิกัดจากการ scan'));
    expect(privacyPolicyTextEn,
        contains('the app does not read or send coordinates from that scan'));
    expect(privacyPolicyTextTh, contains('ลบตำแหน่งที่บันทึกไว้'));
    expect(privacyPolicyTextEn, contains('Clear saved location'));
  });

  test('privacy draft matches current account deletion and sync behavior', () {
    expect(privacyPolicyTextTh, contains('DELETE /account'));
    expect(privacyPolicyTextTh, contains('SUPABASE_SERVICE_ROLE_KEY'));
    expect(privacyPolicyTextTh,
        contains('cloud sync สำหรับข้อมูลสุขภาพถูกปิดไว้'));
    expect(privacyPolicyTextTh, contains('คำขอ HTTPS แบบ GET ไปยัง `/health`'));
    expect(privacyPolicyTextTh,
        contains('ไม่มี access token คำถาม หรือข้อมูลเซนเซอร์'));
    expect(
        privacyPolicyTextTh, isNot(contains('แอปยังไม่มีการลบบัญชี Supabase')));

    expect(privacyPolicyTextEn, contains('DELETE /account'));
    expect(privacyPolicyTextEn, contains('SUPABASE_SERVICE_ROLE_KEY'));
    expect(privacyPolicyTextEn, contains('Google Sheets may retain revision history'));
    expect(privacyPolicyTextEn,
        contains('Cloud health-data sync is currently disabled in the app'));
    expect(privacyPolicyTextEn, contains('HEALTH_DATA_SYNC_ENABLED=true'));
    expect(privacyPolicyTextEn,
        contains('the prompt may include mean Red/IR raw ADC counts'));
    expect(privacyPolicyTextEn,
        contains('the app converts the IMU raw counts before including them'));
    expect(privacyPolicyTextEn, contains('HTTPS GET request to `/health`'));
    expect(privacyPolicyTextEn,
        contains('contains no access token, chat question, or sensor values'));
  });

  test('profile payload does not treat notice acceptance as data consent', () {
    final profile = DozState().userProfile;

    expect(profile, contains('privacyPolicyVersion'));
    expect(profile, isNot(contains('consentScopes')));
  });

  test('draft explicitly separates notice acknowledgement from AI consent', () {
    expect(privacyPolicyTextTh, contains('ต้องแยกเป็นความยินยอมที่เลือกได้'));
    expect(
        privacyPolicyTextEn, contains('requires a separate optional opt-in'));
  });

  test('reviewable Markdown export stays synchronized with the in-app draft',
      () {
    final exported = File('docs/PRIVACY_NOTICE_DRAFT.md').readAsStringSync();
    expect(exported, contains(privacyPolicyTextTh));
    expect(exported, contains(privacyPolicyTextEn));
    expect(exported,
        contains('Generated from `lib/legal/privacy_policy_draft.dart`'));
  });
}
