import 'package:flutter/material.dart';

Future<bool> showPrivacyPolicyDialog(BuildContext context) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: const Color(0xFF11141B),
        title: const Text('Privacy Policy'),
        content: const SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              privacyPolicyText,
              style: TextStyle(color: Colors.white, height: 1.35),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ปิด'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ยอมรับ'),
          ),
        ],
      );
    },
  );
  return accepted ?? false;
}

const privacyPolicyText = '''
Dzoz
ปรับปรุงล่าสุด: [21/06/69] เวอร์ชัน: 1.0
Dzoz ให้ความสำคัญกับความเป็นส่วนตัวและความปลอดภัยของข้อมูลผู้ใช้งาน นโยบายฉบับนี้จัดทำขึ้นให้สอดคล้องกับพระราชบัญญัติคุ้มครองข้อมูลส่วนบุคคล พ.ศ. 2562 (PDPA) และอธิบายถึงการเก็บรวบรวม ใช้ เปิดเผย
นโยบายส่วนบุคคล

1. ข้อมูลที่มีการเก็บรวบรวม
ระบบเก็บรวบรวมข้อมูลดังต่อไปนี้
    • ข้อมูลส่วนตัว: อายุ เพศ ส่วนสูง น้ำหนัก และข้อมูลติดต่อที่ใช้ในการลงทะเบียน เช่น ชื่อ อีเมล
    • ข้อมูลสุขภาพ (ข้อมูลส่วนบุคคลที่มีความอ่อนไหวตามมาตรา 26 ของ PDPA): อัตราการเต้นของหัวใจ (HR) ค่าออกซิเจนในเลือด (SpO₂) อุณหภูมิผิวหนัง และข้อมูลการเคลื่อนไหว
    • ข้อมูลที่ผู้ใช้งานกรอกเพิ่มเติม เพื่อช่วยเพิ่มความแม่นยำของระบบ
    • ข้อมูลการใช้งานแอปพลิเคชันและอุปกรณ์ เช่น ประเภทอุปกรณ์ ระบบปฏิบัติการ และบันทึกการใช้งาน (log)

เนื่องจากข้อมูลสุขภาพเป็นข้อมูลส่วนบุคคลที่มีความอ่อนไหว เราจะเก็บรวบรวมและประมวลผลข้อมูลดังกล่าวก็ต่อเมื่อได้รับ ความยินยอมโดยชัดแจ้ง จากผู้ใช้งานก่อนเท่านั้น

2. ฐานทางกฎหมายและวัตถุประสงค์ในการใช้ข้อมูล
วัตถุประสงค์    ฐานทางกฎหมาย
ประเมินความเสี่ยงด้านสุขภาพเบื้องต้นและแจ้งเตือนผู้ใช้งาน    ความยินยอมโดยชัดแจ้ง
ปรับปรุงประสิทธิภาพและความแม่นยำของระบบ AI    ความยินยอมโดยชัดแจ้ง
ใช้เพื่อการศึกษา วิจัย และพัฒนาโครงงาน    ความยินยอมโดยชัดแจ้ง / ข้อมูลที่ไม่ระบุตัวตนแล้ว
วิเคราะห์ประสิทธิภาพของระบบในภาพรวม    ประโยชน์โดยชอบด้วยกฎหมายของผู้ควบคุมข้อมูล
ดูแลความปลอดภัยของระบบและป้องกันการใช้งานผิดวัตถุประสงค์    ประโยชน์โดยชอบด้วยกฎหมายของผู้ควบคุมข้อมูล

3. ระยะเวลาในการจัดเก็บข้อมูล
เราจะเก็บรักษาข้อมูลส่วนบุคคลไว้ตราบเท่าที่จำเป็นต่อวัตถุประสงค์ที่ระบุไว้ในนโยบายนี้ หรือไม่เกิน [ระบุระยะเวลา เช่น 24 เดือนหลังบัญชีไม่มีการใช้งาน] นับแต่วันที่เก็บรวบรวม เว้นแต่กฎหมายกำหนดให้เก็บไว้นานกว่านั้น เมื่อพ้นระยะเวลาดังกล่าว ข้อมูลจะถูกลบหรือทำให้ไม่สามารถระบุตัวตนได้

4. การเปิดเผยข้อมูล
Dzoz จะไม่เปิดเผยข้อมูลส่วนบุคคลแก่บุคคลภายนอก เว้นแต่
    • ได้รับความยินยอมจากผู้ใช้งาน
    • เป็นไปตามข้อกำหนดของกฎหมายหรือคำสั่งของหน่วยงานรัฐที่มีอำนาจ
    • เป็นข้อมูลที่ผ่านการลบข้อมูลระบุตัวตนแล้วและใช้เพื่อการศึกษา วิจัย หรือพัฒนาระบบ
    • เป็นการเปิดเผยให้แก่ผู้ประมวลผลข้อมูลส่วนบุคคลที่เราว่าจ้าง เช่น ผู้ให้บริการคลาวด์สำหรับจัดเก็บข้อมูล (เช่น [ระบุผู้ให้บริการ]) ซึ่งจะประมวลผลข้อมูลตามคำสั่งของเราเท่านั้นและอยู่ภายใต้ข้อตกลงรักษาความลับ

หากมีการโอนข้อมูลไปยังต่างประเทศ เราจะดำเนินการให้ประเทศปลายทางมีมาตรฐานการคุ้มครองข้อมูลที่เพียงพอตามที่กฎหมายกำหนด

5. การจัดเก็บและมาตรการรักษาความปลอดภัย
ข้อมูลของผู้ใช้งานจะถูกจัดเก็บโดยมีมาตรการรักษาความปลอดภัยที่เหมาะสม ได้แก่ การเข้ารหัสข้อมูลระหว่างการส่งและขณะจัดเก็บ การจำกัดสิทธิ์การเข้าถึงเฉพาะผู้ที่ได้รับอนุญาต การบันทึกประวัติการเข้าถึงข้อมูล (audit log) และการทบทวนมาตรการความปลอดภัยอย่างสม่ำเสมอ เพื่อป้องกันการเข้าถึง การแก้ไข หรือการเปิดเผยข้อมูลโดยไม่ได้รับอนุญาต

6. สิทธิของเจ้าของข้อมูล
ผู้ใช้งานมีสิทธิดังต่อไปนี้ตามที่กฎหมายกำหนด
    • สิทธิเข้าถึงและขอรับสำเนาข้อมูลของตนเอง
    • สิทธิขอแก้ไขข้อมูลที่ไม่ถูกต้องหรือไม่เป็นปัจจุบัน
    • สิทธิขอให้ลบหรือทำลายข้อมูล
    • สิทธิคัดค้านการเก็บรวบรวม ใช้ หรือเปิดเผยข้อมูล
    • สิทธิขอให้ระงับการใช้ข้อมูลชั่วคราว
    • สิทธิขอรับโอนย้ายข้อมูล (data portability) ไปยังผู้ควบคุมข้อมูลรายอื่น
    • สิทธิถอนความยินยอมได้ทุกเมื่อ โดยไม่กระทบต่อความชอบด้วยกฎหมายของการประมวลผลที่ทำไปแล้วก่อนการถอนความยินยอม

ผู้ใช้งานสามารถใช้สิทธิข้างต้นได้โดยติดต่อผ่านช่องทางที่ระบุไว้ในส่วนต้นของนโยบายนี้ เราจะดำเนินการตามคำขอภายในระยะเวลาที่กฎหมายกำหนด

7. ข้อมูลของผู้เยาว์
หากผู้ใช้งานมีอายุต่ำกว่า 20 ปีบริบูรณ์ หรืออายุต่ำกว่าเกณฑ์ที่กฎหมายกำหนดให้ต้องได้รับความยินยอมจากผู้ใช้อำนาจปกครอง การให้ความยินยอมเก็บรวบรวมและใช้ข้อมูลส่วนบุคคลจะต้องได้รับความยินยอมจากผู้ใช้อำนาจปกครองก่อนการใช้งานระบบ

8. ข้อจำกัดความรับผิดชอบ
Dzoz เป็นระบบสำหรับประเมินความเสี่ยงด้านสุขภาพเบื้องต้นเท่านั้น ไม่ใช่เครื่องมือแพทย์และไม่ใช้สำหรับการวินิจฉัยโรค ผลลัพธ์ที่แสดงเป็นเพียงข้อมูลประกอบการตัดสินใจ ไม่สามารถใช้แทนคำแนะนำ การตรวจรักษา หรือการวินิจฉัยจากแพทย์หรือบุคลากรทางการแพทย์ได้ หากพบความผิดปกติร้ายแรงหรือเป็นเหตุฉุกเฉิน โปรดติดต่อสถานพยาบาลหรือสายด่วนการแพทย์ฉุกเฉิน 1669 ทันที

9. การร้องเรียน
หากผู้ใช้งานเห็นว่าเราไม่ปฏิบัติตามนโยบายนี้หรือกฎหมายคุ้มครองข้อมูลส่วนบุคคล สามารถร้องเรียนมายังเราตามช่องทางที่ระบุไว้ข้างต้น หรือร้องเรียนต่อสำนักงานคณะกรรมการคุ้มครองข้อมูลส่วนบุคคล (สคส.) ได้โดยตรง

10. การเปลี่ยนแปลงนโยบาย
ผู้พัฒนาขอสงวนสิทธิ์ในการปรับปรุงหรือแก้ไขนโยบายความเป็นส่วนตัวฉบับนี้ตามความเหมาะสม โดยจะแจ้งให้ผู้ใช้งานทราบเมื่อมีการเปลี่ยนแปลงที่สำคัญผ่านช่องทาง [ระบุช่องทาง เช่น ในแอปพลิเคชันหรืออีเมล]

การใช้งานระบบ Dzoz ถือว่าผู้ใช้งานได้อ่าน เข้าใจ และยอมรับนโยบายความเป็นส่วนตัวฉบับนี้แล้ว

Dzoz
Last Updated: [21/06/2026] Version: 1.0
Dzoz is committed to protecting the privacy and security of our users' data. This Privacy Policy is drafted in alignment with Thailand's Personal Data Protection Act B.E. 2562 (2019) (PDPA) and explains how we collect, use, disclose, and protect personal data.

1. Information We Collect
We collect the following categories of data:
    • Personal information: age, gender, height, weight, and registration contact details such as name, email, or phone number
    • Health data (sensitive personal data under Section 26 of the PDPA): heart rate (HR), blood oxygen saturation (SpO₂), skin temperature, and movement data
    • Additional information provided by the user to help improve the accuracy of the system
    • App and device usage data, such as device type, operating system, and usage logs

Because health data is classified as sensitive personal data, we will only collect and process it after obtaining explicit consent from the user.

2. Legal Basis and Purposes of Processing
Purpose    Legal Basis
Preliminary health risk assessment and user alerts    Explicit consent
Improving the accuracy and performance of the AI system    Explicit consent
Education, research, and project development    Explicit consent / De-identified data
Overall system performance analysis    Legitimate interest of the data controller
System security and misuse prevention    Legitimate interest of the data controller

3. Data Retention Period
We retain personal data only for as long as necessary to fulfill the purposes described in this policy, or for no more than [specify period, e.g., 24 months after account inactivity], unless a longer retention period is required by law. After this period, data will be deleted or rendered unidentifiable.

4. Disclosure of Information
Dzoz will not disclose personal data to third parties except:
    • With the user's consent
    • As required by law or a lawful order from a competent authority
    • Where data has been de-identified and is used for education, research, or system development
    • To data processors engaged by us, such as cloud service providers used for data storage (e.g., [specify provider]), who process data solely on our instructions and under confidentiality agreements

If data is transferred outside Thailand, we will ensure the receiving country maintains an adequate standard of data protection as required by law.

5. Data Storage and Security Measures
User data is stored using appropriate security measures, including encryption in transit and at rest, access restricted to authorized personnel only, audit logging of data access, and regular review of security controls, in order to prevent unauthorized access, alteration, or disclosure.

6. Your Rights
As a data subject, you have the following rights under applicable law:
    • The right to access and obtain a copy of your data
    • The right to request correction of inaccurate or outdated data
    • The right to request deletion or destruction of your data
    • The right to object to the collection, use, or disclosure of your data
    • The right to request restriction of processing
    • The right to data portability, transferring your data to another data controller
    • The right to withdraw consent at any time, without affecting the lawfulness of processing carried out before withdrawal

You may exercise these rights by contacting us through the channels listed at the top of this policy. We will respond to your request within the timeframe required by law.

7. Children's Data
If a user is under 20 years of age, or under the age threshold requiring parental/guardian consent under applicable law, consent for the collection and use of personal data must be obtained from a parent or legal guardian before using the system.

8. Disclaimer
Dzoz is intended for preliminary health risk assessment only. It is not a medical device and is not intended for disease diagnosis. The results provided are for informational purposes only and do not replace advice, examination, or diagnosis from a physician or qualified healthcare professional. If you notice a serious abnormality or experience a medical emergency, please contact a healthcare facility or emergency medical services (1669 in Thailand) immediately.

9. Complaints
If you believe we have failed to comply with this policy or applicable data protection law, you may file a complaint with us through the contact channels above, or directly with Thailand's Personal Data Protection Committee (PDPC).

10. Changes to This Policy
We reserve the right to update or amend this Privacy Policy as appropriate. Users will be notified of material changes through [specify channel, e.g., in-app notification or email].

By using Dzoz, you acknowledge that you have read, understood, and agreed to this Privacy Policy.
''';
