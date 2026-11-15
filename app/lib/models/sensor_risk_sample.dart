import 'risk_result.dart'; // EN: Import the matching analysis result type. TH: นำเข้าชนิดผลวิเคราะห์ที่สัมพันธ์กัน
import 'sensor_data.dart'; // EN: Import the sensor snapshot type. TH: นำเข้าชนิดข้อมูล snapshot จากเซนเซอร์

class SensorRiskSample {
  // EN: Pair one sensor snapshot with its current analysis. TH: จับคู่ snapshot เซนเซอร์หนึ่งชุดกับผลวิเคราะห์ปัจจุบัน
  const SensorRiskSample({
    // EN: Construct an immutable pair for in-memory history. TH: สร้างคู่ข้อมูลแบบแก้ไขไม่ได้สำหรับประวัติในหน่วยความจำ
    required this.sensorData, // EN: Require the corresponding sensor measurements. TH: บังคับให้มีค่าการวัดที่สัมพันธ์กัน
    required this.riskResult, // EN: Require the analysis result for those measurements. TH: บังคับให้มีผลวิเคราะห์ของค่าชุดนี้
  }); // EN: Finish construction of the immutable pair. TH: จบการสร้างคู่ข้อมูลแบบ immutable

  final SensorData
      sensorData; // EN: Retain the values used by graphs and history views. TH: เก็บค่าที่กราฟและหน้าประวัติใช้
  final RiskResult
      riskResult; // EN: Retain the associated status and explanation. TH: เก็บสถานะและคำอธิบายที่สัมพันธ์กับค่าดังกล่าว
} // EN: Finish the sensor-and-risk history model. TH: จบ model ประวัติเซนเซอร์และผลความเสี่ยง
