import 'package:flutter/material.dart';

// EN: Render a labeled value; the caller decides whether it is live or demo data.
// TH: แสดงค่าพร้อมชื่อ โดยผู้เรียกเป็นผู้กำหนดว่าเป็นข้อมูลจริงหรือข้อมูลสาธิต
class SensorCard extends StatelessWidget {
  const SensorCard({
    super.key,
    required this.title,
    required this.value,
    required this.unit,
    required this.icon,
    this.onTap,
  });

  final String
      title; // EN: Name the measured or displayed quantity. TH: ชื่อค่าที่แสดง
  final String value; // EN: Preformatted display value. TH: ค่าที่จัดรูปแบบแล้ว
  final String unit; // EN: Unit, if applicable. TH: หน่วย เมื่อมี
  final IconData icon; // EN: Visual hint for the quantity. TH: ไอคอนของค่า
  final VoidCallback?
      onTap; // EN: Optional navigation action. TH: การกดเพื่อไปหน้าอื่นเมื่อมี

  @override
  Widget build(BuildContext context) {
    // EN: Fit the same card content to phone and wider layouts.
    // TH: ปรับขนาดการ์ดให้เหมาะกับมือถือและจอกว้าง
    final compact = MediaQuery.sizeOf(context).width < 600;
    final textTheme = Theme.of(context).textTheme;
    final card = Container(
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: const Color(0xFF11141B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF232833)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFEF4444), size: compact ? 22 : 26),
          SizedBox(height: compact ? 7 : 10),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: (compact ? textTheme.labelMedium : textTheme.labelLarge)
                ?.copyWith(
              color: const Color(0xFFA7B0C0),
              height: 1.15,
            ),
          ),
          // EN: Keep the value aligned near the bottom of each grid card.
          // TH: จัดค่าที่แสดงให้อยู่ใกล้ด้านล่างของการ์ดในตาราง
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  style:
                      (compact ? textTheme.titleMedium : textTheme.titleLarge)
                          ?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1,
                  ),
                ),
                // EN: Do not show a unit when the caller supplied none.
                // TH: ไม่แสดงหน่วยเมื่อผู้เรียกไม่ได้ระบุ
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 1),
                    child: Text(
                      unit,
                      style: const TextStyle(color: Color(0xFFA7B0C0)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    // EN: Add tap feedback only for cards with an action.
    // TH: เพิ่มการตอบสนองต่อการกดเฉพาะการ์ดที่มีคำสั่ง
    return onTap == null
        ? card
        : Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: card,
            ),
          );
  }
}
