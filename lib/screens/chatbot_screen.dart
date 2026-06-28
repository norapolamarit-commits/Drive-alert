import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../widgets/chat_bubble.dart';

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DozState>();
    final compact = MediaQuery.sizeOf(context).width < 600;
    final pad = compact ? 8.0 : 16.0;
    final messages = state.chatMessages;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(pad: pad),
        Expanded(
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: pad),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0B0D12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF1C212B)),
            ),
            child: messages.isEmpty && !_sending
                ? const _EmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: messages.length + (_sending ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= messages.length) return const TypingBubble();
                      return ChatBubble(message: messages[index]);
                    },
                  ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 10, pad, pad),
          child: Column(
            children: [
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _QuickPrompt(
                      icon: Icons.monitor_heart_outlined,
                      label: 'วิเคราะห์สุขภาพ',
                      onTap: () => _send('ช่วยวิเคราะห์สุขภาพของฉันตอนนี้'),
                    ),
                    _QuickPrompt(
                      icon: Icons.tips_and_updates_outlined,
                      label: 'ควรทำอะไร',
                      onTap: () => _send('ตอนนี้ฉันควรทำอะไร?'),
                    ),
                    _QuickPrompt(
                      icon: Icons.history,
                      label: 'สรุปแนวโน้ม',
                      onTap: () => _send('สรุปแนวโน้มสุขภาพที่ผ่านมา'),
                    ),
                    _QuickPrompt(
                      icon: Icons.waving_hand_outlined,
                      label: 'ทักทาย',
                      onTap: () => _send('สวัสดี'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF11141B),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFF262C38)),
                      ),
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 4,
                        style: const TextStyle(color: Colors.white),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(_controller.text),
                        decoration: const InputDecoration(
                          hintText: 'ถามเรื่องสุขภาพหรือพิมพ์ทักทาย...',
                          hintStyle: TextStyle(color: Color(0xFF6B7484)),
                          border: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _SendButton(
                    sending: _sending,
                    onTap: () => _send(_controller.text),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _send(String message) async {
    final text = message.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _controller.clear();
    _scrollToBottom();
    await context.read<DozState>().askChatbot(text);
    if (!mounted) return;
    setState(() => _sending = false);
    _scrollToBottom();
  }

  Future<void> _scrollToBottom() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.pad});

  final double pad;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, pad, pad, 4),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF34D399), Color(0xFF10B981)],
              ),
            ),
            child: const Icon(Icons.favorite, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'doz AI',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
              Row(
                children: const [
                  CircleAvatar(radius: 4, backgroundColor: Color(0xFF34D399)),
                  SizedBox(width: 6),
                  Text(
                    'ผู้ช่วยดูแลสุขภาพ • พร้อมใช้งาน',
                    style: TextStyle(color: Color(0xFF8B93A3), fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.chat_bubble_outline, color: Color(0xFF34D399), size: 48),
          SizedBox(height: 12),
          Text(
            'สวัสดี! ฉันคือ doz AI',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 6),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'ถามเรื่องสุขภาพ ขอคำแนะนำการดูแลตัวเอง หรือทักทายพูดคุยกันได้เลย',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF8B93A3), fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.sending, required this.onTap});

  final bool sending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: sending ? null : onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFFF65A5A), Color(0xFFEF4444)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFEF4444).withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: sending
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.send_rounded, color: Colors.white),
      ),
    );
  }
}

class _QuickPrompt extends StatelessWidget {
  const _QuickPrompt({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        onPressed: onTap,
        avatar: Icon(icon, size: 16, color: const Color(0xFF34D399)),
        label: Text(label),
        labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
        backgroundColor: const Color(0xFF11141B),
        side: const BorderSide(color: Color(0xFF262C38)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
}
