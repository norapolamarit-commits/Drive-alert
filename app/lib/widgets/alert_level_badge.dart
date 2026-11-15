import 'package:flutter/material.dart'; // EN: Build the colored status badge. TH: สร้างป้ายสถานะที่มีสี

import '../ui_text.dart'; // EN: Translate known alert levels. TH: แปลระดับแจ้งเตือนที่รู้จัก

class AlertLevelBadge extends StatelessWidget {
  // EN: Render one immutable alert-level label. TH: แสดงป้ายระดับแจ้งเตือนที่ไม่เปลี่ยนภายใน widget
  const AlertLevelBadge(
      {super.key,
      required this.level}); // EN: Require the level to display. TH: รับระดับที่จะแสดง

  final String
      level; // EN: Hold the model's level name. TH: เก็บชื่อระดับจากโมเดล

  Color get color => switch (level) {
        // EN: Map the known level to its display color. TH: จับคู่ระดับที่รู้จักกับสีแสดงผล
        'Safe' => const Color(
            0xFF1B9A59), // EN: Use green for Safe. TH: ใช้สีเขียวสำหรับ Safe
        'Watch' => const Color(
            0xFFF2C94C), // EN: Use yellow for Watch. TH: ใช้สีเหลืองสำหรับ Watch
        'Warning' => const Color(
            0xFFF2994A), // EN: Use orange for Warning. TH: ใช้สีส้มสำหรับ Warning
        'Emergency' => const Color(
            0xFFEB5757), // EN: Use red for Emergency. TH: ใช้สีแดงสำหรับ Emergency
        _ => Colors
            .grey, // EN: Show unknown levels neutrally. TH: แสดงระดับที่ไม่รู้จักด้วยสีกลาง
      }; // EN: Complete the color mapping. TH: จบการจับคู่สี

  @override // EN: Implement the Flutter widget build contract. TH: ใช้สัญญา build ของ Flutter widget
  Widget build(BuildContext context) {
    // EN: Build the badge for the active locale. TH: สร้างป้ายตามภาษาที่ใช้อยู่
    return Container(
      // EN: Wrap the label in a styled capsule. TH: หุ้มข้อความด้วยกรอบทรงแคปซูล
      padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical:
              6), // EN: Space text away from the border. TH: เว้นช่องระหว่างข้อความกับขอบ
      decoration: BoxDecoration(
        // EN: Define the badge background and border. TH: กำหนดพื้นหลังและขอบป้าย
        color: color.withValues(
            alpha:
                0.14), // EN: Tint the background lightly. TH: เติมสีพื้นหลังอ่อน
        borderRadius: BorderRadius.circular(
            999), // EN: Round the badge into a capsule. TH: ทำมุมโค้งเป็นแคปซูล
        border: Border.all(
            color: color.withValues(
                alpha:
                    0.45)), // EN: Outline the badge with its level color. TH: ใช้สีระดับเป็นเส้นขอบ
      ), // EN: Complete the decoration. TH: จบการตกแต่ง
      child: Text(
        // EN: Display the localized level name. TH: แสดงชื่อระดับตามภาษา
        localizedAlertLevel(context,
            level), // EN: Translate only the display text. TH: แปลเฉพาะข้อความที่แสดง
        style: TextStyle(
            color: color,
            fontWeight: FontWeight
                .w700), // EN: Keep text legible and bold. TH: ใช้ข้อความตัวหนาให้อ่านชัด
      ), // EN: Complete the text widget. TH: จบ widget ข้อความ
    ); // EN: Return the styled badge. TH: คืนป้ายที่ตกแต่งแล้ว
  } // EN: Complete the build method. TH: จบเมธอด build
} // EN: Complete the badge widget. TH: จบ widget ป้าย
