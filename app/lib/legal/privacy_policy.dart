import 'package:flutter/material.dart';

import 'privacy_policy_draft.dart' as draft;
import '../ui_text.dart';

// EN: Preserve old names while keeping one current draft source.
// TH: คงชื่อเดิมสำหรับโค้ดเก่าโดยอ้างข้อความร่างฉบับเดียว
const privacyPolicyTextTh = draft.privacyPolicyTextTh;
const privacyPolicyTextEn = draft.privacyPolicyTextEn;
const privacyPolicyText = privacyPolicyTextTh;

/// EN: Show the current bilingual draft and return whether the user accepted it.
/// TH: แสดงประกาศความเป็นส่วนตัวฉบับร่างสองภาษาและคืนผลว่าผู้ใช้ยอมรับหรือไม่
Future<bool> showPrivacyPolicyDialog(
  BuildContext context, {
  String? initialLanguage,
  bool allowAccept = true,
}) async {
  // EN: Prefer the caller's language, otherwise use the current app locale.
  // TH: ใช้ภาษาที่ผู้เรียกระบุ มิฉะนั้นใช้ภาษาปัจจุบันของแอป
  var isThai = initialLanguage == null
      ? Localizations.localeOf(context).languageCode == 'th'
      : initialLanguage == 'Thai';
  // EN: Wait for an explicit accept action; closing resolves to false.
  // TH: รอการกดยอมรับอย่างชัดเจน โดยการปิดจะคืนค่า false
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        backgroundColor: const Color(0xFF11141B),
        title: Row(
          children: [
            Expanded(
              child: Text(uiText(
                context,
                english: 'Privacy notice — draft',
                thai: 'ประกาศความเป็นส่วนตัว — ฉบับร่าง',
              )),
            ),
            // EN: Switch the notice language without dismissing the dialog.
            // TH: สลับภาษาข้อความโดยไม่ปิดหน้าต่าง
            SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: true, label: Text('ไทย')),
                ButtonSegment(value: false, label: Text('EN')),
              ],
              selected: {isThai},
              onSelectionChanged: (selection) =>
                  setState(() => isThai = selection.first),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              isThai ? privacyPolicyTextTh : privacyPolicyTextEn,
              style: const TextStyle(color: Colors.white, height: 1.4),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(isThai ? 'ปิด' : 'Close'),
          ),
          // EN: Hide the accept action when this dialog is view-only.
          // TH: ซ่อนปุ่มยอมรับเมื่อเปิดเพื่ออ่านอย่างเดียว
          if (allowAccept)
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(isThai ? 'เข้าใจแล้ว' : 'I understand'),
            ),
        ],
      ),
    ),
  );
  return accepted ?? false;
}
