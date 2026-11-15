class ChatMessage {
  // EN: Represent one in-memory chat message. TH: แทนข้อความแชตหนึ่งรายการในหน่วยความจำ
  ChatMessage({
    // EN: Create a message from its text, sender role, and optional time. TH: สร้างข้อความจากเนื้อหา ผู้ส่ง และเวลาที่อาจระบุ
    required this.text, // EN: Require the message text. TH: บังคับให้มีเนื้อหาข้อความ
    required this.isUser, // EN: Require whether the current user sent it. TH: บังคับระบุว่าผู้ใช้เป็นผู้ส่งหรือไม่
    DateTime?
        timestamp, // EN: Accept a source timestamp when one is available. TH: รับเวลาจากต้นทางเมื่อมี
  }) : timestamp = timestamp ??
            DateTime
                .now(); // EN: Use the current local time only when no timestamp was provided. TH: ใช้เวลาปัจจุบันในเครื่องเมื่อไม่ได้ระบุเวลา

  final String
      text; // EN: Store the rendered message content. TH: เก็บเนื้อหาข้อความที่จะแสดง
  final bool
      isUser; // EN: Store the sender role for chat alignment and styling. TH: เก็บบทบาทผู้ส่งเพื่อจัดแนวและรูปแบบข้อความ
  final DateTime
      timestamp; // EN: Store when this message was created. TH: เก็บเวลาที่สร้างข้อความ
} // EN: Finish the chat-message model. TH: จบ model ข้อความแชต
