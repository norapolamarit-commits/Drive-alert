import 'package:flutter/material.dart';

import '../models/chat_message.dart';

/// EN: Dark teal keeps white user text readable. TH: สีเขียวเข้มช่วยให้ข้อความสีขาวอ่านชัด
const chatUserBubbleColors = [Color(0xFF0B6254), Color(0xFF087F68)];

// EN: Render one chat message with sender-specific alignment and time.
// TH: แสดงข้อความแชตหนึ่งรายการพร้อมตำแหน่งตามผู้ส่งและเวลา
class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.message});

  final ChatMessage
      message; // EN: Content, sender flag, and timestamp. TH: เนื้อหา ผู้ส่ง และเวลา

  // EN: Format the message time in local 24-hour notation. TH: จัดเวลาแบบ 24 ชั่วโมง
  String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final isUser = message
        .isUser; // EN: Choose the user's style when true. TH: เลือกรูปแบบข้อความผู้ใช้เมื่อเป็นจริง

    // EN: Limit bubble width so long text remains readable on wide displays.
    // TH: จำกัดความกว้างฟองข้อความให้อ่านง่ายบนจอกว้าง
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: isUser
            ? const LinearGradient(
                colors: chatUserBubbleColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isUser ? null : const Color(0xFF161A22),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isUser ? 16 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 16),
        ),
        border: isUser ? null : Border.all(color: const Color(0xFF262C38)),
      ),
      child: Text(
        message.text,
        style: const TextStyle(color: Colors.white, height: 1.35, fontSize: 14),
      ),
    );

    // EN: Place the timestamp directly below the message body.
    // TH: วางเวลาไว้ใต้เนื้อหาข้อความ
    final column = Column(
      crossAxisAlignment:
          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        bubble,
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
          child: Text(
            _time(message.timestamp),
            style: const TextStyle(color: Color(0xFF6B7484), fontSize: 10),
          ),
        ),
      ],
    );

    // EN: Put user messages right and assistant messages left with an avatar.
    // TH: วางข้อความผู้ใช้ด้านขวาและข้อความผู้ช่วยด้านซ้ายพร้อมไอคอน
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            const _BotAvatar(),
            const SizedBox(width: 8),
          ],
          Flexible(child: column),
        ],
      ),
    );
  }
}

// EN: Draw the assistant avatar used by messages and typing state.
// TH: วาดไอคอนผู้ช่วยสำหรับข้อความและสถานะกำลังพิมพ์
class _BotAvatar extends StatelessWidget {
  const _BotAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFF34D399), Color(0xFF10B981)],
        ),
      ),
      child: const Icon(Icons.favorite, size: 17, color: Colors.white),
    );
  }
}

/// EN: Show an animated waiting indicator while a response is pending.
/// TH: แสดงตัวบ่งชี้กำลังรอคำตอบแบบเคลื่อนไหว
class TypingBubble extends StatelessWidget {
  const TypingBubble({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          _BotAvatar(),
          SizedBox(width: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xFF161A22),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: SizedBox(width: 34, height: 8, child: _Dots()),
            ),
          ),
        ],
      ),
    );
  }
}

// EN: Own the three animated dots used inside the waiting bubble.
// TH: จัดการจุดเคลื่อนไหวสามจุดภายในฟองรอคำตอบ
class _Dots extends StatefulWidget {
  const _Dots();

  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  // EN: Repeat one opacity cycle per second while mounted.
  // TH: วนรอบความทึบทุกหนึ่งวินาทีตราบเท่าที่ widget ยังทำงาน
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    // EN: Release the ticker when this waiting indicator disappears.
    // TH: คืนทรัพยากร animation เมื่อเลิกแสดงตัวบ่งชี้
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(3, (i) {
            // EN: Offset each dot in time to create a traveling pulse.
            // TH: เลื่อนจังหวะแต่ละจุดเพื่อให้เห็นการเคลื่อนไหวต่อเนื่อง
            final t = (_c.value + i * 0.2) % 1.0;
            final opacity = 0.3 + 0.7 * (t < 0.5 ? t * 2 : (1 - t) * 2);
            return Opacity(
              opacity: opacity,
              child: const CircleAvatar(
                radius: 4,
                backgroundColor: Color(0xFF8B93A3),
              ),
            );
          }),
        );
      },
    );
  }
}
