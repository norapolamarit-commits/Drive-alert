import 'package:flutter/foundation.dart'; // EN: Limit diagnostics to debug builds. TH: จำกัด diagnostics ไว้เฉพาะ debug build
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // EN: Deliver operating-system notifications. TH: ส่ง notification ผ่านระบบปฏิบัติการ

import '../models/risk_result.dart'; // EN: Read the app's alert level and associated result. TH: อ่านระดับแจ้งเตือนและผลที่เกี่ยวข้องของแอป

class NotificationService {
  // EN: Manage local notification setup and alert display. TH: จัดการการตั้งค่าและการแสดง notification ในเครื่อง
  final FlutterLocalNotificationsPlugin
      _plugin = // EN: Create the platform notification adapter. TH: สร้างตัวเชื่อมต่อ notification ของแต่ละแพลตฟอร์ม
      FlutterLocalNotificationsPlugin(); // EN: Retain one plugin instance for this service. TH: เก็บ plugin instance เดียวไว้ใช้ใน service นี้

  bool _initialized =
      false; // EN: Track whether plugin initialization succeeded. TH: ติดตามว่า initialize plugin สำเร็จหรือไม่
  bool _permissionGranted =
      false; // EN: Track the user's notification permission state. TH: ติดตามสถานะสิทธิ์ notification ของผู้ใช้

  bool get initialized =>
      _initialized; // EN: Expose initialization state without allowing mutation. TH: เปิดให้อ่านสถานะ initialize โดยไม่ให้แก้ค่า
  bool get permissionGranted =>
      _permissionGranted; // EN: Expose permission state without allowing mutation. TH: เปิดให้อ่านสถานะสิทธิ์โดยไม่ให้แก้ค่า

  Future<bool> initialize() async {
    // EN: Initialize the plugin and request notification permission. TH: initialize plugin และขอสิทธิ์ notification
    const androidSettings = // EN: Configure Android's notification icon. TH: ตั้งค่าไอคอน notification ของ Android
        AndroidInitializationSettings(
            '@mipmap/ic_launcher'); // EN: Use the app launcher icon. TH: ใช้ไอคอน launcher ของแอป
    const darwinSettings = DarwinInitializationSettings(
      // EN: Avoid prompting for permission during plugin initialization. TH: ไม่แสดง prompt ขอสิทธิ์ระหว่าง initialize plugin
      requestAlertPermission:
          false, // EN: Defer alert permission to the explicit request step. TH: เลื่อนการขอสิทธิ์ alert ไปขั้นตอนที่เรียกอย่างชัดเจน
      requestBadgePermission:
          false, // EN: Defer badge permission to the explicit request step. TH: เลื่อนการขอสิทธิ์ badge ไปขั้นตอนที่เรียกอย่างชัดเจน
      requestSoundPermission:
          false, // EN: Defer sound permission to the explicit request step. TH: เลื่อนการขอสิทธิ์เสียงไปขั้นตอนที่เรียกอย่างชัดเจน
    ); // EN: Finish Apple-platform initialization settings. TH: จบค่าตั้งเริ่มต้นของแพลตฟอร์ม Apple
    const settings = InitializationSettings(
      // EN: Combine platform-specific initialization settings. TH: รวมค่าตั้งเริ่มต้นของแต่ละแพลตฟอร์ม
      android:
          androidSettings, // EN: Apply Android-specific settings. TH: ใช้ค่าตั้งเฉพาะ Android
      iOS:
          darwinSettings, // EN: Apply Apple settings on iOS. TH: ใช้ค่าตั้ง Apple บน iOS
      macOS:
          darwinSettings, // EN: Apply Apple settings on macOS. TH: ใช้ค่าตั้ง Apple บน macOS
    ); // EN: Finish the cross-platform settings object. TH: จบ object ค่าตั้งข้ามแพลตฟอร์ม

    _initialized = await _plugin.initialize(settings: settings) ??
        false; // EN: Initialize the plugin and treat a null result as failure. TH: initialize plugin และถือ null ว่าล้มเหลว
    _permissionGranted =
        await requestPermission(); // EN: Request permission after plugin initialization. TH: ขอสิทธิ์หลัง initialize plugin
    return _initialized &&
        _permissionGranted; // EN: Report success only when both prerequisites pass. TH: รายงานสำเร็จเมื่อผ่านทั้งสองเงื่อนไข
  } // EN: Finish notification initialization. TH: จบการ initialize notification

  Future<bool> requestPermission() async {
    // EN: Ask each supported OS for notification permission. TH: ขอสิทธิ์ notification จากระบบปฏิบัติการที่รองรับ
    final android = _plugin
        .resolvePlatformSpecificImplementation< // EN: Get the Android-specific notification API. TH: เรียก API notification เฉพาะ Android
            AndroidFlutterLocalNotificationsPlugin>(); // EN: Select the Android plugin implementation. TH: เลือก implementation plugin สำหรับ Android
    final androidGranted = await android
        ?.requestNotificationsPermission(); // EN: Request Android notification permission when available. TH: ขอสิทธิ์ Android เมื่อมี implementation

    final ios = _plugin
        .resolvePlatformSpecificImplementation< // EN: Get the iOS-specific notification API. TH: เรียก API notification เฉพาะ iOS
            IOSFlutterLocalNotificationsPlugin>(); // EN: Select the iOS plugin implementation. TH: เลือก implementation plugin สำหรับ iOS
    final iosGranted = await ios?.requestPermissions(
      // EN: Request visible and audible notifications on iOS. TH: ขอ notification ที่แสดงและมีเสียงบน iOS
      alert:
          true, // EN: Request permission for alert banners. TH: ขอสิทธิ์แสดงแถบแจ้งเตือน
      badge:
          true, // EN: Request permission for app-icon badges. TH: ขอสิทธิ์แสดง badge บนไอคอนแอป
      sound:
          true, // EN: Request permission for notification sounds. TH: ขอสิทธิ์เล่นเสียง notification
    ); // EN: Finish the iOS permission request. TH: จบคำขอสิทธิ์ iOS

    final macOS = _plugin
        .resolvePlatformSpecificImplementation< // EN: Get the macOS-specific notification API. TH: เรียก API notification เฉพาะ macOS
            MacOSFlutterLocalNotificationsPlugin>(); // EN: Select the macOS plugin implementation. TH: เลือก implementation plugin สำหรับ macOS
    final macOSGranted = await macOS?.requestPermissions(
      // EN: Request visible and audible notifications on macOS. TH: ขอ notification ที่แสดงและมีเสียงบน macOS
      alert:
          true, // EN: Request permission for alert banners. TH: ขอสิทธิ์แสดงแถบแจ้งเตือน
      badge:
          true, // EN: Request permission for app-icon badges. TH: ขอสิทธิ์แสดง badge บนไอคอนแอป
      sound:
          true, // EN: Request permission for notification sounds. TH: ขอสิทธิ์เล่นเสียง notification
    ); // EN: Finish the macOS permission request. TH: จบคำขอสิทธิ์ macOS

    _permissionGranted = androidGranted ??
        iosGranted ??
        macOSGranted ??
        true; // EN: Use the available platform result, defaulting to supported non-Apple/non-Android platforms. TH: ใช้ผลจากแพลตฟอร์มที่มี และตั้งค่าเริ่มต้นสำหรับแพลตฟอร์มอื่น
    return _permissionGranted; // EN: Return the permission decision to the caller. TH: คืนผลการอนุญาตให้ caller
  } // EN: Finish notification-permission handling. TH: จบการจัดการสิทธิ์ notification

  Future<bool> showRiskAlert({
    // EN: Show a generic local alert and report whether delivery succeeded. TH: แสดง notification ทั่วไปและรายงานว่าส่งสำเร็จหรือไม่
    required RiskResult
        riskResult, // EN: Receive the result used to choose urgency. TH: รับผลที่ใช้กำหนดระดับความเร่งด่วน
  }) async {
    // EN: Perform plugin calls without blocking the UI thread. TH: เรียก plugin แบบ asynchronous ไม่บล็อก UI
    try {
      // EN: Convert OS-plugin failures into a safe delivery result. TH: แปลงความผิดพลาดจาก OS plugin เป็นผลส่งที่ปลอดภัย
      if (!_initialized) {
        // EN: Initialize lazily if the app has not done so already. TH: initialize เมื่อแอปยังไม่ได้ทำก่อนหน้านี้
        await initialize(); // EN: Complete setup and permission handling before showing. TH: ตั้งค่าและจัดการสิทธิ์ให้เสร็จก่อนแสดง
      } // EN: Finish the lazy initialization guard. TH: จบการตรวจ initialize แบบ lazy
      if (!_initialized || !_permissionGranted) {
        return false; // EN: Require both a ready plugin and granted permission. TH: บังคับให้ plugin พร้อมและได้รับอนุญาตทั้งคู่
      } // EN: Finish the notification readiness guard. TH: จบการตรวจความพร้อม notification

      final isEmergency = riskResult.alertLevel ==
          'Emergency'; // EN: Preserve higher urgency for emergency alerts. TH: คงความเร่งด่วนที่สูงกว่าสำหรับ Emergency
      final title =
          isEmergency // EN: Select a title without including a diagnosis or measurements. TH: เลือกหัวข้อโดยไม่ใส่การวินิจฉัยหรือค่าการวัด
              ? 'Emergency health alert' // EN: Mark the urgent case without revealing specific values. TH: ระบุเหตุเร่งด่วนโดยไม่เปิดเผยค่ารายตัว
              : 'Health warning detected'; // EN: Use a generic title for other warning levels. TH: ใช้หัวข้อทั่วไปสำหรับระดับเตือนอื่น
      final body =
          isEmergency // EN: Keep health details out of operating-system previews. TH: ซ่อนรายละเอียดสุขภาพจาก preview ของระบบปฏิบัติการ
              ? 'Check the wearer now. Open the app for details.' // EN: Prompt an immediate check without revealing measurements. TH: ให้ตรวจผู้สวมใส่ทันทีโดยไม่เปิดเผยค่าการวัด
              : 'A health notification is available. Open the app for details.'; // EN: Direct the user to the app for private details. TH: ให้เปิดแอปเพื่อดูรายละเอียดส่วนตัว

      final details = NotificationDetails(
        // EN: Configure display and urgency for each platform. TH: ตั้งค่าการแสดงผลและความเร่งด่วนของแต่ละแพลตฟอร์ม
        android: AndroidNotificationDetails(
          // EN: Configure the Android notification channel and behavior. TH: ตั้ง channel และพฤติกรรม notification ของ Android
          'doz_health_alerts', // EN: Use the stable channel ID registered by the app. TH: ใช้ channel ID คงที่ที่แอปลงทะเบียน
          'Health alerts', // EN: Set the user-visible Android channel name. TH: ตั้งชื่อ channel ที่ผู้ใช้เห็นบน Android
          channelDescription:
              'Risk detection alerts from doz', // EN: Explain what notifications in this channel mean. TH: อธิบายความหมาย notification ใน channel นี้
          importance: isEmergency
              ? Importance.max
              : Importance
                  .high, // EN: Raise emergency notifications above normal warnings. TH: ให้ Emergency สำคัญกว่าการเตือนทั่วไป
          priority: isEmergency
              ? Priority.max
              : Priority
                  .high, // EN: Set the corresponding Android display priority. TH: ตั้ง priority การแสดงผล Android ให้สอดคล้องกัน
          category: AndroidNotificationCategory
              .alarm, // EN: Mark alerts as alarm-like notifications. TH: จัดประเภทแจ้งเตือนเป็นลักษณะ alarm
          playSound:
              true, // EN: Request a sound when platform policy permits it. TH: ขอเล่นเสียงเมื่อ policy ของระบบอนุญาต
          enableVibration:
              true, // EN: Request vibration when platform policy permits it. TH: ขอการสั่นเมื่อ policy ของระบบอนุญาต
          visibility: NotificationVisibility
              .private, // EN: Keep Android lock-screen content private for every alert level. TH: ซ่อนเนื้อหาบนหน้าจอล็อก Android ทุกระดับ
        ), // EN: Finish Android notification details. TH: จบรายละเอียด notification Android
        iOS: const DarwinNotificationDetails(
          // EN: Configure Apple's mobile notification presentation. TH: ตั้งค่าการแสดง notification บนระบบ Apple มือถือ
          presentAlert:
              true, // EN: Allow the system to present an alert. TH: อนุญาตให้ระบบแสดง alert
          presentBadge:
              true, // EN: Allow the system to update the app badge. TH: อนุญาตให้ระบบอัปเดต badge แอป
          presentSound:
              true, // EN: Allow the system to play the configured sound. TH: อนุญาตให้ระบบเล่นเสียงที่กำหนด
        ), // EN: Finish iOS notification details. TH: จบรายละเอียด notification iOS
        macOS: const DarwinNotificationDetails(
          // EN: Configure Apple's desktop notification presentation. TH: ตั้งค่าการแสดง notification บนเดสก์ท็อป Apple
          presentAlert:
              true, // EN: Allow the system to present an alert. TH: อนุญาตให้ระบบแสดง alert
          presentBadge:
              true, // EN: Allow the system to update the app badge. TH: อนุญาตให้ระบบอัปเดต badge แอป
          presentSound:
              true, // EN: Allow the system to play the configured sound. TH: อนุญาตให้ระบบเล่นเสียงที่กำหนด
        ), // EN: Finish macOS notification details. TH: จบรายละเอียด notification macOS
      ); // EN: Finish the cross-platform notification configuration. TH: จบค่าตั้ง notification ข้ามแพลตฟอร์ม

      await _plugin.show(
        // EN: Ask the operating system to display the notification. TH: ขอให้ระบบปฏิบัติการแสดง notification
        id: DateTime.now().millisecondsSinceEpoch.remainder(
            0x7fffffff), // EN: Keep the ID within Android's signed 32-bit range. TH: จำกัด ID ให้อยู่ในช่วง signed 32-bit ของ Android
        title:
            title, // EN: Provide the selected generic alert title. TH: ส่งหัวข้อแจ้งเตือนทั่วไปที่เลือกไว้
        body:
            body, // EN: Provide text that contains no sensor values or recommendation. TH: ส่งข้อความที่ไม่มีค่าจากเซนเซอร์หรือคำแนะนำ
        notificationDetails:
            details, // EN: Apply the platform-specific privacy and urgency settings. TH: ใช้ค่าความเป็นส่วนตัวและความเร่งด่วนของแต่ละแพลตฟอร์ม
      ); // EN: Finish the notification request. TH: จบคำขอแสดง notification
      return true; // EN: Confirm that the plugin accepted the notification request. TH: ยืนยันว่า plugin รับคำขอ notification แล้ว
    } catch (error) {
      // EN: Handle platform errors without exposing health data. TH: จัดการ error ของระบบโดยไม่เปิดเผยข้อมูลสุขภาพ
      if (kDebugMode) {
        // EN: Log diagnostics only in development builds. TH: บันทึก diagnostics เฉพาะ build เพื่อพัฒนา
        debugPrint(
            'Notification delivery failed: ${error.runtimeType}'); // EN: Log only the exception type. TH: log เฉพาะชนิด exception
      } // EN: Finish debug-only diagnostics. TH: จบ diagnostics เฉพาะ debug
      return false; // EN: Let the caller show an accurate failure status. TH: ให้ caller แสดงสถานะล้มเหลวตามจริง
    } // EN: Finish safe plugin-failure handling. TH: จบการจัดการ plugin failure แบบปลอดภัย
  } // EN: Finish risk-alert notification handling. TH: จบการจัดการ notification ความเสี่ยง
} // EN: Finish the notification service. TH: จบ notification service
