import 'package:flutter/material.dart';

/// แสดง dialog นโยบายความเป็นส่วนตัว พร้อมสลับภาษาได้ในตัว (ไม่ต้องพึ่ง state ภายนอก)
/// [initialLanguage] รับค่า 'Thai' หรือ 'English' (ค่าอื่น/ไม่ระบุ → เริ่มที่ไทย)
Future<bool> showPrivacyPolicyDialog(
  BuildContext context, {
  String? initialLanguage,
}) async {
  var isThai = initialLanguage != 'English';
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF11141B),
            title: Row(
              children: [
                const Expanded(child: Text('Privacy Policy')),
                _LanguageToggle(
                  isThai: isThai,
                  onChanged: (value) => setState(() => isThai = value),
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
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(isThai ? 'ยอมรับ' : 'Accept'),
              ),
            ],
          );
        },
      );
    },
  );
  return accepted ?? false;
}

class _LanguageToggle extends StatelessWidget {
  const _LanguageToggle({required this.isThai, required this.onChanged});

  final bool isThai;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: const [
        ButtonSegment(value: true, label: Text('ไทย')),
        ButtonSegment(value: false, label: Text('EN')),
      ],
      selected: {isThai},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

// ── Backward-compat: เผื่อโค้ดอื่นยังอ้างชื่อเดิม ──────────────────────────────
const privacyPolicyText = privacyPolicyTextTh;

const privacyPolicyTextTh = '''
doz — นโยบายความเป็นส่วนตัว
ปรับปรุงล่าสุด: 11 กรกฎาคม 2569 (2026-07-11) เวอร์ชัน: 1.1

doz ให้ความสำคัญกับความเป็นส่วนตัวและความปลอดภัยของข้อมูลผู้ใช้งาน นโยบายฉบับนี้จัดทำขึ้นให้สอดคล้องกับพระราชบัญญัติคุ้มครองข้อมูลส่วนบุคคล พ.ศ. 2562 (PDPA) และอธิบายถึงการเก็บรวบรวม ใช้ เปิดเผย และคุ้มครองข้อมูลส่วนบุคคลของผู้ใช้งาน

1. ข้อมูลที่มีการเก็บรวบรวม
ระบบเก็บรวบรวมข้อมูลดังต่อไปนี้
    • ข้อมูลส่วนตัว: อายุ เพศ วันเกิด ส่วนสูง น้ำหนัก และชื่อผู้ใช้งาน
    • ข้อมูลสุขภาพ (ข้อมูลส่วนบุคคลที่มีความอ่อนไหวตามมาตรา 26 ของ PDPA): อัตราการเต้นของหัวใจ (HR) ค่าออกซิเจนในเลือด (SpO₂) ความแปรปรวนของอัตราการเต้นหัวใจ (HRV) ค่าการนำไฟฟ้าของผิวหนัง (GSR) อุณหภูมิร่างกาย ข้อมูลการเคลื่อนไหว (accelerometer/gyroscope) และโรคประจำตัว/ภาวะสุขภาพที่ผู้ใช้งานระบุเพิ่มเติมในโปรไฟล์
    • ผลการประเมินความเสี่ยงและประวัติการแจ้งเตือน ที่ระบบคำนวณจากข้อมูลข้างต้น
    • ข้อมูลตำแหน่งที่ตั้ง (GPS) เมื่อผู้ใช้งานอนุญาตการเข้าถึงตำแหน่ง — ใช้เพื่อบันทึกตำแหน่งขณะเกิดเหตุแจ้งเตือนเท่านั้น
    • ข้อมูลผู้ติดต่อฉุกเฉิน (ชื่อและเบอร์โทรศัพท์ของบุคคลที่สาม) ที่ผู้ใช้งานกรอกเอง — โปรดแจ้งและได้รับความยินยอมจากบุคคลดังกล่าวก่อนกรอกข้อมูลนี้ ข้อมูลนี้ใช้แสดงในแอปพลิเคชันของท่านเท่านั้น ระบบจะไม่ติดต่อบุคคลดังกล่าวโดยอัตโนมัติ
    • ข้อมูลอุปกรณ์และการเชื่อมต่อ: รหัสอุปกรณ์ (device ID) สถานะการเชื่อมต่อบลูทูธกับอุปกรณ์สวมใส่ ระดับแบตเตอรี่
    • ข้อมูลการใช้งานแอปพลิเคชัน เช่น ประเภทอุปกรณ์ ระบบปฏิบัติการ และบันทึกการใช้งาน (log)

เนื่องจากข้อมูลสุขภาพเป็นข้อมูลส่วนบุคคลที่มีความอ่อนไหว เราจะเก็บรวบรวมและประมวลผลข้อมูลดังกล่าวก็ต่อเมื่อได้รับ ความยินยอมโดยชัดแจ้ง จากผู้ใช้งานก่อนเท่านั้น

2. ฐานทางกฎหมายและวัตถุประสงค์ในการใช้ข้อมูล
    • ประเมินความเสี่ยงด้านสุขภาพเบื้องต้นและแจ้งเตือนผู้ใช้งาน — ความยินยอมโดยชัดแจ้ง
    • สร้างคำแนะนำการดูแลสุขภาพส่วนบุคคลผ่านระบบผู้ช่วย AI (เมื่อเปิดใช้ฟีเจอร์นี้) — ความยินยอมโดยชัดแจ้ง
    • ปรับปรุงประสิทธิภาพและความแม่นยำของระบบ — ความยินยอมโดยชัดแจ้ง / ข้อมูลที่ไม่ระบุตัวตนแล้ว
    • ดูแลความปลอดภัยของระบบและป้องกันการใช้งานผิดวัตถุประสงค์ — ประโยชน์โดยชอบด้วยกฎหมายของผู้ควบคุมข้อมูล

3. การประมวลผลด้วย AI และการส่งข้อมูลไปยังผู้ให้บริการภายนอก
เมื่อผู้ใช้งานเปิดใช้ฟีเจอร์คำแนะนำอัจฉริยะ ระบบจะส่ง "สรุปค่าสัญญาณชีพ" และ "สถานะความเสี่ยงที่ตรวจพบ" (ไม่รวมชื่อหรือข้อมูลระบุตัวตนโดยตรง) ไปยังผู้ให้บริการประมวลผลภาษาด้วย AI เพื่อสร้างคำแนะนำ ข้อมูลนี้อาจถูกประมวลผลบนเซิร์ฟเวอร์ที่ตั้งอยู่นอกประเทศไทย หากไม่ต้องการใช้ฟีเจอร์นี้ ผู้ใช้งานสามารถปิดการเชื่อมต่อคลาวด์ได้ในหน้าตั้งค่าอุปกรณ์ ระบบจะยังคงให้คำแนะนำพื้นฐานจากกฎที่ตั้งไว้ล่วงหน้า (offline) แทน

4. ระยะเวลาในการจัดเก็บข้อมูล
ข้อมูลสุขภาพ ประวัติการแจ้งเตือน และผลการประเมินความเสี่ยง จะถูกจัดเก็บไว้ในอุปกรณ์ของท่านจนกว่าท่านจะลบข้อมูลด้วยตนเอง (ผ่านเมนู โปรไฟล์ > นโยบายความเป็นส่วนตัว > "Delete all my data") หรือถอนการติดตั้งแอปพลิเคชัน ปัจจุบันระบบยังไม่มีการลบข้อมูลอัตโนมัติตามระยะเวลา หากท่านเปิดใช้การซิงก์ข้อมูลกับคลาวด์ ข้อมูลที่ซิงก์ไว้จะถูกเก็บรักษาไว้จนกว่าท่านจะร้องขอให้ลบหรือปิดการซิงก์ ทั้งนี้ข้อมูลอาจถูกเก็บไว้นานกว่านั้นหากกฎหมายกำหนด

5. การเปิดเผยข้อมูล
doz จะไม่เปิดเผยข้อมูลส่วนบุคคลแก่บุคคลภายนอก เว้นแต่
    • ได้รับความยินยอมจากผู้ใช้งาน
    • เป็นไปตามข้อกำหนดของกฎหมายหรือคำสั่งของหน่วยงานรัฐที่มีอำนาจ
    • เป็นข้อมูลที่ผ่านการลบข้อมูลระบุตัวตนแล้วและใช้เพื่อการศึกษา วิจัย หรือพัฒนาระบบ
    • เป็นการเปิดเผยให้แก่ผู้ประมวลผลข้อมูลส่วนบุคคลที่เราว่าจ้าง ได้แก่ ผู้ให้บริการคลาวด์สำหรับจัดเก็บและซิงก์ข้อมูล และผู้ให้บริการประมวลผลภาษาด้วย AI ตามที่ระบุในข้อ 3 ซึ่งจะประมวลผลข้อมูลตามคำสั่งของเราเท่านั้นและอยู่ภายใต้ข้อตกลงรักษาความลับ

หากมีการโอนข้อมูลไปยังต่างประเทศ เราจะดำเนินการให้ประเทศปลายทางมีมาตรฐานการคุ้มครองข้อมูลที่เพียงพอตามที่กฎหมายกำหนด

6. การจัดเก็บและมาตรการรักษาความปลอดภัย
ข้อมูลของผู้ใช้งานจะถูกจัดเก็บโดยมีมาตรการรักษาความปลอดภัยที่เหมาะสม ได้แก่ การเข้ารหัสข้อมูลระหว่างการส่ง การจำกัดสิทธิ์การเข้าถึงเฉพาะผู้ที่ได้รับอนุญาต และการทบทวนมาตรการความปลอดภัยอย่างสม่ำเสมอ เพื่อป้องกันการเข้าถึง การแก้ไข หรือการเปิดเผยข้อมูลโดยไม่ได้รับอนุญาต

การแจ้งเตือนผ่านระบบปฏิบัติการ (push notification) อาจแสดงข้อมูลสรุป เช่น ระดับความเสี่ยงหรือค่าสัญญาณชีพ บนหน้าจอล็อกของอุปกรณ์ หากท่านกังวลเรื่องความเป็นส่วนตัวในจุดนี้ โปรดตรวจสอบการตั้งค่าการแสดงตัวอย่างการแจ้งเตือนบนหน้าจอล็อกของอุปกรณ์ท่าน

7. สิทธิของเจ้าของข้อมูล
ผู้ใช้งานมีสิทธิดังต่อไปนี้ตามที่กฎหมายกำหนด
    • สิทธิเข้าถึงและขอรับสำเนาข้อมูลของตนเอง — สามารถส่งออกข้อมูลค่าเซนเซอร์เป็นไฟล์ CSV ได้ทันทีที่เมนู โปรไฟล์ > "Export sensor history CSV"
    • สิทธิขอแก้ไขข้อมูลที่ไม่ถูกต้องหรือไม่เป็นปัจจุบัน — แก้ไขได้เองที่เมนู โปรไฟล์ > "Edit personal information"
    • สิทธิขอให้ลบหรือทำลายข้อมูล — ลบได้ทันทีที่เมนู โปรไฟล์ > นโยบายความเป็นส่วนตัว > "Delete all my data" (ลบประวัติการแจ้งเตือนและ log เซนเซอร์ทั้งหมดบนอุปกรณ์)
    • สิทธิคัดค้านการเก็บรวบรวม ใช้ หรือเปิดเผยข้อมูล
    • สิทธิขอให้ระงับการใช้ข้อมูลชั่วคราว
    • สิทธิขอรับโอนย้ายข้อมูล (data portability) ไปยังผู้ควบคุมข้อมูลรายอื่น
    • สิทธิถอนความยินยอมได้ทุกเมื่อ โดยไม่กระทบต่อความชอบด้วยกฎหมายของการประมวลผลที่ทำไปแล้วก่อนการถอนความยินยอม

สำหรับสิทธิที่ไม่สามารถดำเนินการได้เองในแอปพลิเคชัน โปรดติดต่อผ่านช่องทาง: norapolamarit@gmail.com เราจะดำเนินการตามคำขอภายในระยะเวลาที่กฎหมายกำหนด

8. ข้อมูลของผู้เยาว์
หากผู้ใช้งานมีอายุต่ำกว่า 20 ปีบริบูรณ์ หรืออายุต่ำกว่าเกณฑ์ที่กฎหมายกำหนดให้ต้องได้รับความยินยอมจากผู้ใช้อำนาจปกครอง การให้ความยินยอมเก็บรวบรวมและใช้ข้อมูลส่วนบุคคลจะต้องได้รับความยินยอมจากผู้ใช้อำนาจปกครองก่อนการใช้งานระบบ

9. ข้อจำกัดความรับผิดชอบ
doz เป็นระบบต้นแบบสำหรับประเมินความเสี่ยงด้านสุขภาพเบื้องต้นเท่านั้น ไม่ใช่เครื่องมือแพทย์และไม่ใช้สำหรับการวินิจฉัยโรค ผลลัพธ์และคำแนะนำที่แสดง (รวมถึงคำแนะนำจากระบบ AI) เป็นเพียงข้อมูลประกอบการตัดสินใจ ไม่สามารถใช้แทนคำแนะนำ การตรวจรักษา หรือการวินิจฉัยจากแพทย์หรือบุคลากรทางการแพทย์ได้ หากพบความผิดปกติร้ายแรงหรือเป็นเหตุฉุกเฉิน โปรดติดต่อสถานพยาบาลหรือสายด่วนการแพทย์ฉุกเฉิน 1669 ทันที

10. การร้องเรียน
หากผู้ใช้งานเห็นว่าเราไม่ปฏิบัติตามนโยบายนี้หรือกฎหมายคุ้มครองข้อมูลส่วนบุคคล สามารถร้องเรียนมายังเราตามช่องทางที่ระบุไว้ในข้อ 7 หรือร้องเรียนต่อสำนักงานคณะกรรมการคุ้มครองข้อมูลส่วนบุคคล (สคส.) ได้โดยตรง

11. การเปลี่ยนแปลงนโยบาย
ผู้พัฒนาขอสงวนสิทธิ์ในการปรับปรุงหรือแก้ไขนโยบายความเป็นส่วนตัวฉบับนี้ตามความเหมาะสม โดยจะแจ้งให้ผู้ใช้งานทราบเมื่อมีการเปลี่ยนแปลงที่สำคัญผ่านหน้าจอแจ้งเตือนภายในแอปพลิเคชัน และจะปรับหมายเลขเวอร์ชันของนโยบายทุกครั้งที่มีการแก้ไขสาระสำคัญ

การใช้งานระบบ doz ถือว่าผู้ใช้งานได้อ่าน เข้าใจ และยอมรับนโยบายความเป็นส่วนตัวฉบับนี้แล้ว
''';

const privacyPolicyTextEn = '''
doz — Privacy Policy
Last updated: 11 July 2026 Version: 1.1

doz is committed to protecting the privacy and security of our users' data. This Privacy Policy is drafted in alignment with Thailand's Personal Data Protection Act B.E. 2562 (2019) (PDPA) and explains how we collect, use, disclose, and protect personal data.

1. Information We Collect
We collect the following categories of data:
    • Personal information: age, gender, date of birth, height, weight, and display name
    • Health data (sensitive personal data under Section 26 of the PDPA): heart rate (HR), blood oxygen saturation (SpO₂), heart-rate variability (HRV), galvanic skin response (GSR), body temperature, motion data (accelerometer/gyroscope), and any underlying medical conditions you add to your profile
    • Risk assessment results and alert history computed from the data above
    • Location data (GPS), only when you grant location permission — used solely to record where an alert occurred
    • Emergency contact information (a third party's name and phone number) that you provide yourself — please obtain that person's consent before entering their details. This is shown only within your own app and is never contacted automatically by the system
    • Device and connection data: device ID, Bluetooth connection status with your wearable, and battery level
    • App usage data, such as device type, operating system, and usage logs

Because health data is classified as sensitive personal data, we will only collect and process it after obtaining explicit consent from the user.

2. Legal Basis and Purposes of Processing
    • Preliminary health risk assessment and user alerts — Explicit consent
    • Generating personalized health guidance via the AI assistant feature (when enabled) — Explicit consent
    • Improving the accuracy and performance of the system — Explicit consent / De-identified data
    • System security and misuse prevention — Legitimate interest of the data controller

3. AI Processing and Transfers to Third-Party Providers
When you enable the AI advice feature, the app sends a summary of your current vital signs and detected risk status (without your name or other direct identifiers) to a third-party AI language-model provider to generate advice. This data may be processed on servers located outside Thailand. You can disable cloud sync in device settings at any time; the app will continue to provide rule-based offline guidance instead.

4. Data Retention Period
Health data, alert history, and risk results are stored on your device until you delete them yourself (via Profile > Privacy Policy > "Delete all my data") or uninstall the app. There is currently no automatic time-based deletion. If you enable cloud sync, synced data is retained until you request deletion or disable sync. Data may be retained longer where required by law.

5. Disclosure of Information
doz will not disclose personal data to third parties except:
    • With the user's consent
    • As required by law or a lawful order from a competent authority
    • Where data has been de-identified and is used for education, research, or system development
    • To data processors engaged by us — namely the cloud hosting provider used to store and sync data, and the AI language-model provider referenced in Section 3 — who process data solely on our instructions and under confidentiality agreements

If data is transferred outside Thailand, we will ensure the receiving country maintains an adequate standard of data protection as required by law.

6. Data Storage and Security Measures
User data is stored using appropriate security measures, including encryption in transit, access restricted to authorized personnel only, and regular review of security controls, in order to prevent unauthorized access, alteration, or disclosure.

Operating-system push notifications may display a summary such as risk level or vital-sign values on your device's lock screen. If this is a privacy concern, please review your device's notification-preview settings.

7. Your Rights
As a data subject, you have the following rights under applicable law:
    • The right to access and obtain a copy of your data — export your sensor history as CSV any time from Profile > "Export sensor history CSV"
    • The right to request correction of inaccurate or outdated data — edit it yourself from Profile > "Edit personal information"
    • The right to request deletion or destruction of your data — delete it instantly from Profile > Privacy Policy > "Delete all my data" (clears all on-device alert history and sensor logs)
    • The right to object to the collection, use, or disclosure of your data
    • The right to request restriction of processing
    • The right to data portability, transferring your data to another data controller
    • The right to withdraw consent at any time, without affecting the lawfulness of processing carried out before withdrawal

For rights that cannot be exercised directly in the app, please contact us at: norapolamarit@gmail.com. We will respond to your request within the timeframe required by law.

8. Children's Data
If a user is under 20 years of age, or under the age threshold requiring parental/guardian consent under applicable law, consent for the collection and use of personal data must be obtained from a parent or legal guardian before using the system.

9. Disclaimer
doz is a prototype intended for preliminary health risk assessment only. It is not a medical device and is not intended for disease diagnosis. The results and advice provided (including AI-generated advice) are for informational purposes only and do not replace advice, examination, or diagnosis from a physician or qualified healthcare professional. If you notice a serious abnormality or experience a medical emergency, please contact a healthcare facility or emergency medical services (1669 in Thailand) immediately.

10. Complaints
If you believe we have failed to comply with this policy or applicable data protection law, you may file a complaint with us through the contact channel in Section 7, or directly with Thailand's Personal Data Protection Committee (PDPC).

11. Changes to This Policy
We reserve the right to update or amend this Privacy Policy as appropriate. Users will be notified of material changes via an in-app notice, and the version number will be updated whenever a material change is made.

By using doz, you acknowledge that you have read, understood, and agreed to this Privacy Policy.
''';
