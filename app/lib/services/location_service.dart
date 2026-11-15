import 'package:geolocator/geolocator.dart'; // EN: Read location only after checking OS permission. TH: อ่านตำแหน่งหลังตรวจสิทธิ์ของระบบปฏิบัติการ

class LocationService {
  // EN: Centralize the app's explicit current-location request. TH: รวมการขอตำแหน่งปัจจุบันที่แอปเรียกใช้อย่างชัดเจน
  Future<Position> getCurrentPosition() async {
    // EN: Resolve the current coordinates asynchronously. TH: ขอพิกัดปัจจุบันแบบ asynchronous
    final serviceEnabled = await Geolocator
        .isLocationServiceEnabled(); // EN: Check whether device location services are enabled. TH: ตรวจว่าบริการตำแหน่งของเครื่องเปิดอยู่หรือไม่
    if (!serviceEnabled) {
      // EN: Stop before requesting a location when system services are off. TH: หยุดก่อนขอตำแหน่งเมื่อบริการระบบปิด
      throw const LocationServiceException(
          'Location service is disabled.'); // EN: Return a safe, non-sensitive explanation to the caller. TH: ส่งคำอธิบายที่ไม่เปิดเผยข้อมูลอ่อนไหวกลับ caller
    } // EN: Finish the system-service guard. TH: จบการตรวจบริการระบบ

    var permission = await Geolocator
        .checkPermission(); // EN: Read the current app-level location permission. TH: อ่านสิทธิ์ตำแหน่งปัจจุบันของแอป
    if (permission == LocationPermission.denied) {
      // EN: Request permission only after an initial denial. TH: ขอสิทธิ์เมื่อผลตรวจครั้งแรกเป็น denied
      permission = await Geolocator
          .requestPermission(); // EN: Ask the user through the operating system prompt. TH: ขอให้ผู้ใช้อนุญาตผ่านหน้าต่างของระบบปฏิบัติการ
    } // EN: Finish the conditional permission request. TH: จบการขอสิทธิ์ตามเงื่อนไข
    if (permission == LocationPermission.denied) {
      // EN: Stop if the user denied the request. TH: หยุดเมื่อผู้ใช้ปฏิเสธคำขอ
      throw const LocationServiceException(
          'Location permission was denied.'); // EN: Report denial without exposing coordinates. TH: แจ้งการปฏิเสธโดยไม่เปิดเผยพิกัด
    } // EN: Finish the denied-permission guard. TH: จบการตรวจกรณีปฏิเสธสิทธิ์
    if (permission == LocationPermission.deniedForever) {
      // EN: Detect permission that requires changing Settings. TH: ตรวจสิทธิ์ที่ต้องแก้จากหน้าตั้งค่า
      throw const LocationServiceException(
        // EN: Create a specific error for the permanently denied state. TH: สร้าง error เฉพาะกรณีปฏิเสธถาวร
        'Location permission is permanently denied.', // EN: Explain why another in-app prompt cannot be shown. TH: อธิบายว่าแอปไม่สามารถแสดง prompt ขอซ้ำได้
      ); // EN: Finish constructing the permission error. TH: จบการสร้าง error สิทธิ์
    } // EN: Finish the permanently denied guard. TH: จบการตรวจการปฏิเสธถาวร

    return Geolocator.getCurrentPosition(
      // EN: Read one current position after permission checks pass. TH: อ่านตำแหน่งปัจจุบันหนึ่งครั้งหลังผ่านการตรวจสิทธิ์
      locationSettings: const LocationSettings(
        // EN: Use fixed settings to bound accuracy and wait time. TH: ใช้ค่าตั้งคงที่เพื่อกำหนดความแม่นและเวลารอ
        accuracy: LocationAccuracy
            .high, // EN: Request high accuracy because this is an explicit user action. TH: ขอความแม่นสูงเมื่อผู้ใช้เรียกใช้ฟังก์ชันนี้
        timeLimit: Duration(
            seconds:
                10), // EN: Stop waiting after ten seconds. TH: หยุดรอเมื่อครบสิบวินาที
      ), // EN: Finish the location settings object. TH: จบ object ค่าตั้งตำแหน่ง
    ); // EN: Return the position result to the caller. TH: คืนผลตำแหน่งให้ caller
  } // EN: Finish the current-position operation. TH: จบการขอตำแหน่งปัจจุบัน
} // EN: Finish the location service. TH: จบ service ตำแหน่ง

class LocationServiceException implements Exception {
  // EN: Represent expected location permission or service failures. TH: แทนความผิดพลาดที่คาดหมายจากสิทธิ์หรือบริการตำแหน่ง
  const LocationServiceException(
      this.message); // EN: Store the safe explanation created by the service. TH: เก็บคำอธิบายที่ปลอดภัยจาก service

  final String
      message; // EN: Retain the message for user-facing handling. TH: เก็บข้อความสำหรับให้แอปจัดการหรือแสดงผล

  @override // EN: Mark the standard exception string conversion override. TH: ระบุว่า override การแปลง exception เป็น string
  String toString() =>
      message; // EN: Return only the safe message. TH: คืนเฉพาะข้อความที่ปลอดภัย
} // EN: Finish the location exception type. TH: จบชนิด exception ของตำแหน่ง
