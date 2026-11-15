import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../legal/privacy_policy.dart';
import '../main.dart';
import '../ui_text.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final TextEditingController _nameController;
  DateTime? _privacyAcceptedAt;
  bool _privacyAccepted = false;

  String _copy(String en, String th) => uiText(context, english: en, thai: th);

  @override
  void initState() {
    super.initState();
    final state = context.read<DozState>();
    _nameController = TextEditingController(text: state.userName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: AppLanguageToggle(
                language: context.watch<DozState>().language,
                onChanged: (language) => unawaited(
                  context
                      .read<DozState>()
                      .updateSettings(newLanguage: language),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const _SetupHero(),
            const SizedBox(height: 28),
            TextFormField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              maxLength: 40,
              buildCounter: (context,
                      {required currentLength,
                      required isFocused,
                      maxLength}) =>
                  null,
              decoration: InputDecoration(
                labelText: _copy('Name (optional)', 'ชื่อเล่น (ไม่บังคับ)'),
                hintText:
                    _copy('What should we call you?', 'ต้องการให้เรียกว่าอะไร'),
                prefixIcon: const Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF11141B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF232833)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.privacy_tip_outlined,
                      color: Color(0xFF55D6A7)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _copy(
                        'No health details are needed to start. Age, weight, height, gender, and conditions are not used by the current sensor display or analysis. You can add profile details later if you choose.',
                        'เริ่มใช้งานได้โดยไม่ต้องกรอกข้อมูลสุขภาพ อายุ น้ำหนัก ส่วนสูง เพศ และโรคประจำตัวยังไม่ถูกใช้กับการแสดงผลหรือวิเคราะห์เซนเซอร์ปัจจุบัน หากต้องการสามารถเพิ่มในโปรไฟล์ภายหลังได้',
                      ),
                      style: const TextStyle(
                          color: Color(0xFFA7B0C0), height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _PrivacyPolicyAccept(
              accepted: _privacyAccepted,
              onChanged: _handlePrivacyAccepted,
              onShowPolicy: _openPrivacyPolicyFromLink,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _privacyAccepted ? _submit : null,
              child: Text(_copy('Continue', 'ดำเนินการต่อ')),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    final state = context.read<DozState>();
    state.completeSetup(
      newName: _nameController.text.trim().isEmpty
          ? _copy('Doz user', 'ผู้ใช้ doz')
          : _nameController.text.trim(),
      newPrivacyPolicyAcceptedAt: _privacyAcceptedAt ?? DateTime.now(),
      newWeight: state.weight,
      newHeight: state.height,
      newAge: state.age,
      newBirthDate: state.birthDate,
      newGender: state.gender,
      newConditions: state.conditions,
      newProfileDetailsProvided: false,
    );
  }

  Future<void> _handlePrivacyAccepted(bool? value) async {
    final accepted = value ?? false;
    if (!accepted) {
      setState(() {
        _privacyAccepted = false;
        _privacyAcceptedAt = null;
      });
      return;
    }

    final dialogAccepted = await showPrivacyPolicyDialog(
      context,
      initialLanguage: Localizations.localeOf(context).languageCode == 'th'
          ? 'Thai'
          : 'English',
    );
    if (!mounted) return;
    setState(() {
      _privacyAccepted = dialogAccepted;
      _privacyAcceptedAt = dialogAccepted ? DateTime.now() : null;
    });
  }

  Future<bool> _openPrivacyPolicyFromLink() async {
    final accepted = await showPrivacyPolicyDialog(
      context,
      initialLanguage: Localizations.localeOf(context).languageCode == 'th'
          ? 'Thai'
          : 'English',
    );
    if (!mounted) return accepted;
    if (accepted) {
      setState(() {
        _privacyAccepted = true;
        _privacyAcceptedAt = DateTime.now();
      });
    }
    return accepted;
  }
}

class _PrivacyPolicyAccept extends StatelessWidget {
  const _PrivacyPolicyAccept({
    required this.accepted,
    required this.onChanged,
    required this.onShowPolicy,
  });

  final bool accepted;
  final ValueChanged<bool?> onChanged;
  final Future<bool> Function() onShowPolicy;

  @override
  Widget build(BuildContext context) {
    String copy(String en, String th) => uiText(context, english: en, thai: th);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF11141B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF232833)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: accepted,
            onChanged: onChanged,
            activeColor: Colors.white,
            checkColor: Colors.black,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  copy('I have read and understand the ', 'ฉันอ่านและเข้าใจ'),
                  style: const TextStyle(color: Colors.white, height: 1.35),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: onShowPolicy,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      copy(' privacy notice ', 'ประกาศความเป็นส่วนตัว'),
                      style: const TextStyle(
                        color: Colors.white,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white,
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
                Text(
                  copy(
                    ' This acknowledgement only confirms that you understand this draft. It is not consent to remote AI or cloud health-data sync. Remote AI asks separately before sending data; cloud health-data sync is currently disabled.',
                    ' การยืนยันนี้เป็นเพียงการรับทราบและเข้าใจประกาศฉบับร่าง ไม่ใช่การยินยอมใช้ AI ระยะไกลหรือซิงก์ข้อมูลสุขภาพขึ้นคลาวด์ หากใช้ AI ระยะไกลจะขอความยินยอมแยกก่อนส่งข้อมูล ส่วน cloud sync ปิดใช้อยู่ในปัจจุบัน',
                  ),
                  style: const TextStyle(color: Colors.white, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SetupHero extends StatelessWidget {
  const _SetupHero();

  @override
  Widget build(BuildContext context) {
    final description = uiText(
      context,
      english: 'Start with the essentials; health details are optional',
      thai: 'เริ่มด้วยข้อมูลเท่าที่จำเป็น ข้อมูลสุขภาพไม่บังคับ',
    );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF11141B),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF232833)),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFF050608),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(
              Icons.watch_outlined,
              color: Color(0xFFEF4444),
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'doz',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(color: Color(0xFFA7B0C0)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
