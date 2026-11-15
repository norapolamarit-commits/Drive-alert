import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../ui_text.dart';
import '../widgets/chat_bubble.dart';

enum ChatSourceMode {
  localOnly,
  signInRequired,
  consentRequired,
  localSelected,
  remoteAi,
}

ChatSourceMode resolveChatSourceMode({
  required bool endpointConfigured,
  required bool signedIn,
  required bool consentValid,
  required bool llmEnabled,
  required bool mockMode,
}) {
  if (!endpointConfigured) return ChatSourceMode.localOnly;
  if (!signedIn) return ChatSourceMode.signInRequired;
  if (!llmEnabled || mockMode) return ChatSourceMode.localSelected;
  if (!consentValid) return ChatSourceMode.consentRequired;
  return ChatSourceMode.remoteAi;
}

bool shouldPromptForRemoteChatConsent({
  required ChatSourceMode mode,
  required bool consentValid,
}) =>
    mode == ChatSourceMode.consentRequired && !consentValid;

/// Describes exactly what remote-chat consent covers in the current app.
/// Local demo/cache readings are never represented as live data in this prompt.
String remoteChatConsentDescription({
  required String destination,
  required bool isThai,
}) {
  if (isThai) {
    return '''ปลายทาง: $destination

แอปจะส่งคำถามไปยังเซิร์ฟเวอร์นี้ หากมีข้อมูลสดจากอุปกรณ์ ข้อความที่ใช้ตอบอาจมีค่าสัญญาณสดและสถานะที่อุปกรณ์ให้มา หากไม่มีข้อมูลสด แอปจะระบุว่าไม่มีข้อมูลสดและไม่ส่งค่าสาธิตหรือค่าที่เก็บค้างไว้

เมื่อสถานะการแจ้งเตือนเปลี่ยน แอปอาจส่งสรุปค่าสัญญาณและสถานะไปยังเซิร์ฟเวอร์เดียวกันเพื่อขอคำแนะนำเพิ่มเติม การตรวจ endpoint สุขภาพหลังอนุญาตจะไม่ส่งข้อมูลเซนเซอร์หรือ token บัญชี แต่เซิร์ฟเวอร์/เครือข่ายอาจได้รับ IP address และข้อมูลคำขอ เซิร์ฟเวอร์หรือผู้ให้บริการ AI ภายนอกอาจประมวลผลเนื้อหาแชต

แอปไม่ส่งชื่อ อายุ เพศ หรือประวัติการแจ้งเตือน การอนุญาตมีผลเฉพาะ URL นี้ และคุณเลือกใช้คำตอบในเครื่องได้''';
  }
  return '''Destination: $destination

Your question will be sent to this server. If fresh readings from a physical device are available, the prompt may include those readings and the status provided by the device. If no fresh readings are available, the app says so and does not send demo or cached readings.

When the alert state changes, the app may send a sensor summary and status to this same server for additional advice. After consent, the health-endpoint check sends no sensor data or account token, but the server/network may receive your IP address and request metadata. The server or an external AI provider may process chat content.

The app does not send your name, age, gender, or alert history. Consent applies only to this URL; you can use local answers instead.''';
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DozState>();
    String copy(String en, String th) => uiText(context, english: en, thai: th);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });

    return Column(
      children: [
        const _ChatHeader(),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
            itemCount: state.chatMessages.length + (state.chatbotBusy ? 1 : 0),
            itemBuilder: (context, index) {
              if (state.chatbotBusy && index == state.chatMessages.length) {
                return const TypingBubble();
              }
              return ChatBubble(message: state.chatMessages[index]);
            },
          ),
        ),
        if (!state.chatMessages.any((message) => message.isUser))
          _SuggestedPrompts(
            onSelected: (prompt) {
              _controller.text = prompt;
              _send(context, state);
            },
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 2000,
                  buildCounter: (context,
                          {required currentLength,
                          required isFocused,
                          maxLength}) =>
                      null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(context, state),
                  decoration: InputDecoration(
                    hintText: copy('Ask about status or app use…',
                        'ถามเกี่ยวกับสถานะหรือการใช้งาน…'),
                    prefixIcon: const Icon(Icons.chat_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: copy('Send message', 'ส่งข้อความ'),
                onPressed:
                    state.chatbotBusy ? null : () => _send(context, state),
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Text(
            copy('AI replies are general information, not a medical diagnosis.',
                'คำตอบจาก AI เป็นข้อมูลทั่วไป ไม่ใช่การวินิจฉัยทางการแพทย์'),
            style: const TextStyle(color: Color(0xFF8B93A3), fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Future<void> _send(BuildContext context, DozState state) async {
    String copy(String en, String th) => uiText(context, english: en, thai: th);
    final text = _controller.text.trim();
    if (text.isEmpty || state.chatbotBusy) return;
    if (text.length > 2000) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(copy('Question exceeds 2,000 characters.',
                'คำถามยาวเกิน 2,000 ตัวอักษร'))),
      );
      return;
    }
    final sourceMode = resolveChatSourceMode(
      endpointConfigured: state.chatbotRemoteConfigured,
      signedIn: state.chatbotRemoteAvailable,
      consentValid: state.chatbotRemoteConsentValid,
      llmEnabled: state.llmEnabled,
      mockMode: state.mockChatbotResponse,
    );
    if (shouldPromptForRemoteChatConsent(
      mode: sourceMode,
      consentValid: state.chatbotRemoteConsentValid,
    )) {
      final endpointUri = Uri.tryParse(state.phratumaEndpoint);
      final destination = endpointUri == null
          ? 'unavailable'
          : '${endpointUri.host}${endpointUri.hasPort ? ':${endpointUri.port}' : ''}${endpointUri.path}';
      final consent = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(copy(
              'Allow sending this question to AI?', 'อนุญาตส่งคำถามให้ AI?')),
          content: Text(remoteChatConsentDescription(
            destination: destination,
            isThai: Localizations.localeOf(context).languageCode == 'th',
          )),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(copy('Use local mode', 'ใช้โหมดในเครื่อง')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(copy('Allow and send', 'อนุญาตและส่ง')),
            ),
          ],
        ),
      );
      if (!context.mounted) return;
      if (consent == true) await state.setChatbotRemoteConsent(true);
      if (!context.mounted) return;
    }
    _controller.clear();
    await state.askChatbot(text);
  }
}

class _SuggestedPrompts extends StatelessWidget {
  const _SuggestedPrompts({required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    String copy(String en, String th) => uiText(context, english: en, thai: th);
    final prompts = [
      (
        label: copy('Connect device', 'เชื่อมต่ออุปกรณ์'),
        question: copy('How do I connect Bluetooth?', 'เชื่อมต่ออุปกรณ์ยังไง?'),
      ),
      (
        label: copy('Red / IR readings', 'ค่า Red / IR'),
        question: copy(
            'What do Red and IR readings mean?', 'ค่า Red และ IR คืออะไร?'),
      ),
      (
        label: copy('Privacy', 'ความเป็นส่วนตัว'),
        question: copy(
            'What is the privacy policy?', 'ข้อมูลมีความเป็นส่วนตัวอย่างไร?'),
      ),
    ];

    return SizedBox(
      height: 42,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: prompts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) => ActionChip(
          onPressed: () => onSelected(prompts[index].question),
          label: Text(prompts[index].label),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

class _ChatHeader extends StatefulWidget {
  const _ChatHeader();

  @override
  State<_ChatHeader> createState() => _ChatHeaderState();
}

class _ChatHeaderState extends State<_ChatHeader> {
  String?
      _checkedEndpoint; // EN: Cache the endpoint last checked for readiness. TH: เก็บปลายทางที่ตรวจความพร้อมล่าสุด
  bool?
      _serverReady; // EN: Distinguish protected-route readiness from process liveness. TH: แยกความพร้อม route ที่ป้องกันจากการที่ process ยังทำงาน
  bool _checking =
      false; // EN: Track an in-flight readiness request for the header spinner. TH: ติดตามการตรวจ readiness ที่กำลังทำเพื่อแสดงวงหมุน

  @override // EN: Refresh server status when inherited app state changes. TH: อัปเดตสถานะ server เมื่อ state ที่สืบทอดเปลี่ยน
  void didChangeDependencies() {
    // EN: Inspect the currently approved chat destination. TH: ตรวจปลายทางแชตที่อนุญาตอยู่
    super
        .didChangeDependencies(); // EN: Keep Flutter lifecycle handling intact. TH: คงการทำงาน lifecycle ของ Flutter
    final state = context.read<
        DozState>(); // EN: Read the owner of chat configuration. TH: อ่าน state เจ้าของค่าแชต
    final endpoint = state
        .phratumaEndpoint; // EN: Capture one endpoint for this probe cycle. TH: เก็บ endpoint หนึ่งค่าสำหรับรอบตรวจนี้
    if (state.chatbotRemoteConfigured &&
        state.chatbotRemoteConsentValid &&
        _checkedEndpoint != endpoint) {
      _checkedEndpoint =
          endpoint; // EN: Avoid probing the unchanged endpoint again. TH: ไม่ตรวจ endpoint เดิมซ้ำ
      _checking = true; // EN: Show the pending status. TH: แสดงสถานะกำลังตรวจ
      WidgetsBinding.instance.addPostFrameCallback((_) => _probe(
          endpoint)); // EN: Start I/O after the current frame. TH: เริ่ม I/O หลังเฟรมปัจจุบัน
    } else if (!state.chatbotRemoteConfigured ||
        !state.chatbotRemoteConsentValid) {
      _checkedEndpoint =
          null; // EN: Forget the old approved destination. TH: ลืมปลายทางเดิมที่อนุญาต
      _serverReady =
          null; // EN: Avoid showing stale readiness after consent revocation. TH: ไม่แสดง readiness เก่าหลังถอน consent
      _checking = false; // EN: Clear a stale spinner. TH: ล้างวงหมุนที่ค้าง
    }
  }

  Future<void> _probe(String endpoint) async {
    // EN: Check Auth readiness for one approved endpoint. TH: ตรวจความพร้อม Auth ของ endpoint ที่อนุญาตหนึ่งรายการ
    if (!mounted) {
      // EN: Check the widget lifecycle before updating UI. TH: ตรวจ lifecycle ของ widget ก่อนอัปเดต UI
      return; // EN: Stop after this widget has been removed. TH: หยุดเมื่อ widget ถูกถอดแล้ว
    } // EN: Continue only while the header is mounted. TH: ดำเนินต่อเมื่อ header ยังอยู่
    setState(() => _checking =
        true); // EN: Display progress while the network request runs. TH: แสดงกำลังทำงานระหว่างส่งคำขอ
    final ready = await context.read<DozState>().checkChatbotEndpoint(
        endpoint); // EN: Query the server's ready route. TH: ตรวจ route ready ของ server
    if (!mounted || context.read<DozState>().phratumaEndpoint != endpoint) {
      return; // EN: Discard a response for an old endpoint or disposed widget. TH: ทิ้งผลจาก endpoint เก่าหรือ widget ที่ปิดแล้ว
    }
    setState(() {
      _serverReady =
          ready; // EN: Publish the current readiness result. TH: แสดงผล readiness ล่าสุด
      _checking =
          false; // EN: Hide the spinner after the response. TH: ซ่อนวงหมุนหลังได้คำตอบ
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DozState>();
    final mode = resolveChatSourceMode(
      endpointConfigured: state.chatbotRemoteConfigured,
      signedIn: state.chatbotRemoteAvailable,
      consentValid: state.chatbotRemoteConsentValid,
      llmEnabled: state.llmEnabled,
      mockMode: state.mockChatbotResponse,
    );
    final remoteSelected = mode == ChatSourceMode.remoteAi;
    String copy(String en, String th) => uiText(context, english: en, thai: th);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF232833))),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF12352F),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.auto_awesome, color: Color(0xFF55D6A7)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(copy('Ask doz', 'ถาม doz'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        )),
                Text(
                  switch (mode) {
                    ChatSourceMode.localOnly => copy(
                        'Local help only • remote AI is not configured',
                        'ใช้คำตอบในเครื่อง • ยังไม่ได้ตั้งค่า AI ระยะไกล'),
                    ChatSourceMode.signInRequired => copy(
                        'Sign in to use remote AI • local help is available',
                        'เข้าสู่ระบบเพื่อใช้ AI ระยะไกล • ยังใช้คำตอบในเครื่องได้'),
                    ChatSourceMode.consentRequired => copy(
                        'Remote endpoint configured • asks before sending data',
                        'ตั้งค่าเซิร์ฟเวอร์ระยะไกลแล้ว • จะขออนุญาตก่อนส่งข้อมูล'),
                    ChatSourceMode.localSelected => copy(
                        'Local mode selected • remote AI is off',
                        'เลือกโหมดในเครื่อง • ปิด AI ระยะไกลอยู่'),
                    ChatSourceMode.remoteAi => copy(
                        'Remote endpoint selected • response source is shown',
                        'เลือกเซิร์ฟเวอร์ระยะไกลแล้ว • มีป้ายบอกแหล่งคำตอบ'),
                  },
                  style:
                      const TextStyle(color: Color(0xFF8B93A3), fontSize: 12),
                ),
                if (state.chatbotRemoteConfigured) ...[
                  const SizedBox(height: 3),
                  Builder(
                    builder: (context) {
                      final status = !state.chatbotRemoteConsentValid
                          ? copy('Server check starts after remote consent',
                              'จะตรวจเซิร์ฟเวอร์หลังอนุญาตใช้ระบบระยะไกล')
                          : _checking
                              ? copy('Checking chat server…',
                                  'กำลังตรวจเซิร์ฟเวอร์แชต…')
                              : _serverReady == true
                                  ? copy(
                                      'API responds • AI service not verified',
                                      'API ตอบสนอง • ยังไม่ได้ยืนยันบริการ AI')
                                  : copy(
                                      'Chat server unavailable • local replies will be used',
                                      'เซิร์ฟเวอร์แชตไม่พร้อม • จะใช้คำตอบในเครื่อง');
                      return Semantics(
                        liveRegion: true,
                        label: status,
                        child: ExcludeSemantics(
                          child: Text(
                            status,
                            style: TextStyle(
                              color: _serverReady == true
                                  ? const Color(0xFF55D6A7)
                                  : const Color(0xFFFFC56A),
                              fontSize: 11,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          if (state.chatbotRemoteConsentValid)
            IconButton(
              tooltip: copy('Check chat server', 'ตรวจเซิร์ฟเวอร์แชต'),
              onPressed:
                  _checking ? null : () => _probe(state.phratumaEndpoint),
              icon: _checking
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          if (state.chatbotRemoteConsentValid)
            IconButton(
              tooltip: copy(
                'Turn off remote AI and use local answers',
                'ปิด AI ระยะไกลและใช้คำตอบในเครื่อง',
              ),
              onPressed: () => state.setChatbotRemoteConsent(false),
              icon: const Icon(Icons.cloud_off_outlined),
            ),
          Semantics(
            label: remoteSelected
                ? copy(
                    'Remote AI selected • reply availability is not verified',
                    'เลือก AI ระยะไกลแล้ว • ยังไม่ได้ยืนยันว่าตอบกลับได้',
                  )
                : copy('Local assistance mode', 'โหมดช่วยเหลือในเครื่อง'),
            child: Icon(Icons.circle,
                size: 9,
                // A successful /ready probe does not prove that the LLM reply
                // path is working, so do not show a green "active" indicator.
                color:
                    remoteSelected ? Colors.orange : const Color(0xFF55D6A7)),
          ),
        ],
      ),
    );
  }
}
