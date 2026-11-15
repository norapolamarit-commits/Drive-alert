import 'package:flutter/material.dart'; // EN: Use Flutter locale/widget APIs. TH: ใช้ API locale และ widget ของ Flutter

/// EN: Lets first-run users choose a language before opening profile settings.
/// TH: ให้ผู้ใช้ใหม่เลือกภาษาก่อนเข้าหน้าตั้งค่าโปรไฟล์
class AppLanguageToggle extends StatelessWidget {
  // EN: Build the immutable language toggle from current selection and callback.
  // TH: สร้างตัวเลือกภาษาที่ไม่เปลี่ยนค่าเองจากภาษาปัจจุบันและ callback
  const AppLanguageToggle({
    super.key,
    required this.language,
    required this.onChanged,
  });

  final String
      language; // EN: Keep the selected app language. TH: เก็บภาษาที่เลือกในแอป
  final ValueChanged<String>
      onChanged; // EN: Notify the parent when the user selects a language. TH: แจ้ง parent เมื่อผู้ใช้เลือกภาษา

  @override
  Widget build(BuildContext context) {
    // EN: Render a compact two-option language selector. TH: แสดงตัวเลือกภาษาสองแบบขนาดกะทัดรัด
    return SegmentedButton<String>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: const [
        ButtonSegment(value: 'Thai', label: Text('ไทย')),
        ButtonSegment(value: 'English', label: Text('EN')),
      ],
      selected: {
        language == 'Thai' ? 'Thai' : 'English'
      }, // EN: Normalize any non-Thai selection to English. TH: เลือก English เมื่อค่าไม่ใช่ Thai
      onSelectionChanged: (selection) => onChanged(selection
          .first), // EN: Pass the selected language to the owner. TH: ส่งภาษาที่เลือกกลับให้ parent
    );
  }
}

/// EN: Select short UI copy using the locale selected in app settings.
/// TH: เลือกข้อความ UI สั้นตาม locale ที่ผู้ใช้ตั้งไว้ในแอป
String uiText(
  BuildContext context, {
  required String english,
  required String thai,
}) {
  return Localizations.localeOf(context).languageCode == 'th'
      ? thai
      : english; // EN: Use Thai only for the Thai locale and English otherwise. TH: ใช้ภาษาไทยเฉพาะ locale ไทย นอกนั้นใช้ English
}

/// EN: Localize alert labels for display while preserving canonical model values.
/// TH: แปลชื่อระดับแจ้งเตือนตอนแสดงผล โดยคงค่า model มาตรฐานไว้
String localizedAlertLevel(BuildContext context, String level) {
  if (Localizations.localeOf(context).languageCode != 'th') {
    return level; // EN: Keep canonical labels in English locale. TH: คง label มาตรฐานเมื่อใช้ English
  }
  const labels = <String, String>{
    'Safe': 'ปกติ',
    'Watch': 'เฝ้าระวัง',
    'Warning': 'เตือน',
    'Emergency': 'ฉุกเฉิน',
    'Unknown': 'ยังไม่ทราบ',
  };
  return labels[level] ??
      level; // EN: Preserve unknown labels instead of guessing. TH: คง label ที่ไม่รู้จักแทนการเดาคำแปล
}

/// EN: Localize only app-owned risk states; preserve unknown model labels.
/// TH: แปลเฉพาะสถานะ risk ที่แอปกำหนด และคง label จาก model ที่ไม่รู้จัก
String localizedRiskClass(BuildContext context, String riskClass) {
  final isThai = Localizations.localeOf(context).languageCode ==
      'th'; // EN: Cache the active locale check. TH: เก็บผลตรวจ locale ปัจจุบันไว้ใช้ซ้ำ
  if (!isThai) {
    const englishLabels = <String, String>{
      'ปกติ': 'Normal',
      'ตัวอย่างสาธิต': 'Demo preview',
    };
    return englishLabels[riskClass] ??
        riskClass; // EN: Fall back to the source label when unmapped. TH: ใช้ label ต้นทางเมื่อไม่มีคำแปล
  }
  const labels = <String, String>{
    'AI analysis unavailable': 'ยังไม่มีผลวิเคราะห์ AI',
    'Device disconnected': 'อุปกรณ์ถูกตัดการเชื่อมต่อ',
    'Demo preview': 'ตัวอย่างสาธิต',
  };
  return labels[riskClass] ??
      riskClass; // EN: Fall back to the source label when unmapped. TH: ใช้ label ต้นทางเมื่อไม่มีคำแปล
}

/// EN: Translate known app recommendations without rewriting free-form AI advice.
/// TH: แปลคำแนะนำที่แอปสร้างไว้ โดยไม่แก้คำแนะนำ AI แบบอิสระ
String localizedRiskRecommendation(
    BuildContext context, String recommendation) {
  final isThai = Localizations.localeOf(context).languageCode ==
      'th'; // EN: Determine which direction the exact lookup needs. TH: เลือกทิศทางการค้นคำแปลตาม locale

  const translations = <String, String>{
    'ค่าปัจจุบันอยู่ในช่วงปลอดภัย ติดตามต่อเนื่องตามปกติ':
        'Current readings are within the safe range. Continue monitoring as usual.',
    'Connect the wearable to receive data. No risk assessment is available yet.':
        'เชื่อมต่ออุปกรณ์เพื่อรับข้อมูล ขณะนี้ยังไม่มีผลประเมินความเสี่ยง',
    'เริ่มมีสัญญาณง่วง วางแผนหยุดพักใน 15 นาที ดื่มน้ำ และเพิ่มความระมัดระวัง':
        'Early signs of drowsiness detected. Plan to stop and rest within 15 minutes, drink water, and stay alert.',
    'พบสัญญาณหลับในชัดเจน จอดในจุดปลอดภัยทันที งีบ 15-20 นาที ดื่มกาแฟแล้วรอ 20 นาทีก่อนขับต่อ':
        'Clear signs of drowsiness detected. Stop in a safe place now. Consider a 15–20 minute nap; if you use caffeine, wait about 20 minutes before driving again.',
    'หยุดรถ/กิจกรรมทันทีในพื้นที่ปลอดภัย กดตอบรับการแจ้งเตือนถ้ายังตื่นอยู่ หากไม่ตอบสนอง ให้ผู้ดูแล/ฉุกเฉินเข้าตรวจสอบ':
        'Stop the vehicle or activity in a safe place now. Acknowledge the alert if you are responsive; if not, a caregiver or emergency responder should check on you.',
    'ลดความเร็วของกิจกรรม ดื่มน้ำ และพักสั้น ๆ เพื่อประเมินความพร้อม':
        'Slow down, drink water, and take a short break to reassess how you feel.',
    'พักหายใจช้า ๆ 3-5 นาที ลดสิ่งกระตุ้น และติดตามค่าซ้ำอีกครั้ง':
        'Pause and breathe slowly for 3–5 minutes, reduce stimulation, then check again.',
    'หยุดกิจกรรมทันที อยู่ในพื้นที่ปลอดภัย และให้ผู้ดูแลตรวจสอบสถานการณ์':
        'Stop the activity and move to a safe place. Ask a caregiver to check on the situation.',
    'หยุดกิจกรรมทันที ตรวจสอบอาการ และติดต่อผู้ดูแล/1669 หากไม่ดีขึ้น':
        'Stop the activity and check for symptoms. Contact a caregiver or Thailand emergency services (1669) if the condition does not improve.',
    'โหมดสาธิตไม่มีการประเมินความเสี่ยงหรือผลจาก AI':
        'No AI or risk assessment is available in demo mode.',
  };
  if (isThai) {
    final thaiTranslations = <String, String>{
      for (final entry in translations.entries) entry.value: entry.key,
    };
    return thaiTranslations[recommendation] ??
        recommendation; // EN: Reverse the table for Thai-source lookup and preserve unknown text. TH: กลับตารางเพื่อค้นจากข้อความไทยและคงข้อความที่ไม่รู้จัก
  }
  return translations[recommendation] ??
      recommendation; // EN: Translate only exact known recommendations. TH: แปลเฉพาะคำแนะนำที่ตรงกับรายการ
}

/// Localizes known demo provenance labels while leaving device diagnostics untouched.
String localizedRiskSign(BuildContext context, String sign) {
  if (Localizations.localeOf(context).languageCode != 'th') return sign;
  const translations = <String, String>{
    'Demo sensor values are generated for interface preview only.':
        'ค่าจากเซนเซอร์เป็นข้อมูลจำลองสำหรับดูตัวอย่างหน้าจอเท่านั้น',
    'No current reading from a physical device.':
        'ยังไม่มีข้อมูลล่าสุดจากอุปกรณ์จริง',
  };
  return translations[sign] ?? sign;
}

/// Converts the English BLE state kept for logs/storage into user-facing copy.
String localizedBleStatus(BuildContext context, String status) {
  final isThai = Localizations.localeOf(context).languageCode == 'th';
  if (!isThai) return status;

  const exactTranslations = <String, String>{
    'No sensor data yet': 'ยังไม่มีข้อมูลจากเซนเซอร์',
    'Receiving data': 'กำลังรับข้อมูล',
    'Sensor data delayed': 'ข้อมูลจากเซนเซอร์ล่าช้า',
    'Sensor data stale': 'ไม่มีข้อมูลเซนเซอร์ใหม่',
    'Connected; waiting for first sensor packet':
        'เชื่อมต่อแล้ว กำลังรอข้อมูลจากเซนเซอร์ชุดแรก',
    'Mock BLE stream': 'ใช้ข้อมูลสาธิตจากแอป',
    'Mock BLE stream connected': 'เชื่อมต่อโหมดข้อมูลสาธิตแล้ว',
    'BLE connection lost; demo data mode':
        'การเชื่อมต่อขาดแล้ว กำลังแสดงข้อมูลสาธิต',
    'Device disconnected; demo data is shown':
        'อุปกรณ์ถูกตัดการเชื่อมต่อ กำลังแสดงข้อมูลสาธิต',
    'Signed out; device disconnected':
        'ออกจากระบบและยกเลิกการเชื่อมต่ออุปกรณ์แล้ว',
    'Scanning ESP32...': 'กำลังค้นหาอุปกรณ์ ESP32…',
    'BLE scan cancelled': 'ยกเลิกการค้นหา Bluetooth แล้ว',
    'Doz device not found. Check power and BLE advertising; demo data is separate.':
        'ไม่พบอุปกรณ์ Doz ตรวจว่าเปิดเครื่องและประกาศ BLE อยู่ ข้อมูลสาธิตแยกจากอุปกรณ์จริง',
    'Doz device not found. Demo data is separate from BLE connection.':
        'ไม่พบอุปกรณ์ Doz ข้อมูลสาธิตไม่ได้เชื่อมต่อผ่าน BLE',
    'BLE connection failed. Using mock BLE stream.':
        'เชื่อมต่อ Bluetooth ไม่สำเร็จ กำลังใช้ข้อมูลสาธิต',
    'Device forgotten. Mock BLE stream connected':
        'ลืมอุปกรณ์แล้ว เชื่อมต่อโหมดข้อมูลสาธิต',
    'BLE raw telemetry received • AI unavailable':
        'รับข้อมูลดิบจากเซนเซอร์แล้ว • ยังไม่มีผลวิเคราะห์ AI',
  };
  final exact = exactTranslations[status];
  if (exact != null) return exact;

  if (status.startsWith('Device found: ')) {
    return 'พบอุปกรณ์: ${status.substring('Device found: '.length)}';
  }
  if (status.startsWith('Connected to ')) {
    return 'เชื่อมต่อกับ ${status.substring('Connected to '.length)} แล้ว';
  }
  if (status.startsWith('Connecting to ')) {
    return 'กำลังเชื่อมต่อกับ ${status.substring('Connecting to '.length)}';
  }
  if (status == 'Connecting ESP32...') return 'กำลังเชื่อมต่อกับ ESP32…';
  if (status.startsWith('BLE scan failed:')) {
    final detail = status.substring('BLE scan failed:'.length).trim();
    if (detail.toLowerCase().contains('location services')) {
      return 'Android รุ่นนี้ต้องเปิดบริการตำแหน่งของระบบเพื่อค้นหา BLE แอปไม่อ่านพิกัดระหว่างค้นหา';
    }
    if (detail.toLowerCase().contains('off')) {
      return 'Bluetooth ปิดอยู่ เปิด Bluetooth ในการตั้งค่าแล้วลองอีกครั้ง';
    }
    if (detail.toLowerCase().contains('denied') ||
        detail.toLowerCase().contains('permission')) {
      return 'ยังไม่ได้อนุญาต Bluetooth ให้แอป ตรวจสิทธิ์ใน Settings แล้วลองอีกครั้ง';
    }
    if (detail.toLowerCase().contains('unavailable')) {
      return 'อุปกรณ์นี้ไม่รองรับ Bluetooth LE';
    }
    return 'ค้นหา Bluetooth ไม่สำเร็จ ตรวจ Bluetooth และสิทธิ์แอปแล้วลองอีกครั้ง';
  }
  if (status.startsWith('Connection failed:') ||
      status.startsWith('BLE connection failed:')) {
    return 'เชื่อมต่อไม่ได้ ตรวจว่าอุปกรณ์เปิดอยู่และใช้เฟิร์มแวร์ที่รองรับ';
  }
  if (status.startsWith('BLE scan failed')) {
    return 'ค้นหา Bluetooth ไม่สำเร็จ ตรวจการตั้งค่า Bluetooth แล้วลองอีกครั้ง';
  }
  return status;
}

/// Converts known app-owned cloud states to the selected UI language.
String localizedCloudStatus(BuildContext context, String status) {
  final isThai = Localizations.localeOf(context).languageCode == 'th';
  if (!isThai) return status;
  const translations = <String, String>{
    'Cloud sync disabled pending production privacy/security review':
        'ปิดการซิงก์คลาวด์ไว้ ระหว่างรอทบทวนความเป็นส่วนตัวและความปลอดภัย',
    'Syncing sensor to cloud...': 'กำลังส่งข้อมูลเซนเซอร์ไปยังคลาวด์…',
    'Syncing alert to cloud...': 'กำลังส่งการแจ้งเตือนไปยังคลาวด์…',
    'Cloud sync failed': 'ซิงก์ข้อมูลขึ้นคลาวด์ไม่สำเร็จ',
    'Cloud alert sync failed': 'ซิงก์การแจ้งเตือนขึ้นคลาวด์ไม่สำเร็จ',
  };
  final exact = translations[status];
  if (exact != null) return exact;
  if (status.startsWith('Cloud synced ')) {
    return 'ซิงก์ข้อมูลขึ้นคลาวด์แล้ว ${status.substring('Cloud synced '.length)}';
  }
  if (status.startsWith('Alert synced ')) {
    return 'ซิงก์การแจ้งเตือนขึ้นคลาวด์แล้ว ${status.substring('Alert synced '.length)}';
  }
  return status;
}

/// Converts known app-owned sensor states while preserving unknown diagnostics.
String localizedSensorStatus(BuildContext context, String status) {
  final isThai = Localizations.localeOf(context).languageCode == 'th';
  if (!isThai) return status;
  const translations = <String, String>{
    'No sensor data yet': 'ยังไม่มีข้อมูลจากเซนเซอร์',
    'Connected; waiting for first sensor packet':
        'เชื่อมต่อแล้ว กำลังรอข้อมูลเซนเซอร์ชุดแรก',
    'Device disconnected; demo data is shown':
        'อุปกรณ์ถูกตัดการเชื่อมต่อ กำลังแสดงข้อมูลสาธิต',
    'Signed out; account data hidden': 'ออกจากระบบแล้ว ซ่อนข้อมูลบัญชี',
    'Receiving BLE sensor data': 'กำลังรับข้อมูลจากเซนเซอร์ผ่าน BLE',
    'Receiving mock data': 'กำลังแสดงข้อมูลสาธิต',
    'Invalid sensor value received': 'ได้รับค่าจากเซนเซอร์ที่ไม่ถูกต้อง',
    'BLE raw telemetry received • AI unavailable':
        'รับข้อมูลดิบจาก BLE แล้ว • ยังไม่มีผลวิเคราะห์ AI',
  };
  return translations[status] ?? status;
}

/// Localizes app-owned location states without exposing raw platform errors.
String localizedLocationStatus(BuildContext context, String status) {
  final isThai = Localizations.localeOf(context).languageCode == 'th';
  if (!isThai) return status;
  const translations = <String, String>{
    'Location not requested': 'ยังไม่ได้ขอตำแหน่ง',
    'Requesting location...': 'กำลังขอตำแหน่ง…',
    'Location cleared': 'ลบตำแหน่งที่บันทึกไว้แล้ว',
  };
  final exact = translations[status];
  if (exact != null) return exact;
  if (status.startsWith('Location ready: ')) {
    return 'พร้อมใช้งาน • ${status.substring('Location ready: '.length)}';
  }
  if (status.startsWith('Location unavailable:')) {
    return 'ไม่สามารถอ่านตำแหน่งได้ ตรวจสิทธิ์และการตั้งค่าตำแหน่ง';
  }
  return status;
}
