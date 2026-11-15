// ESP32-S3 sensor acquisition stream for sensor_ai_pipeline.py.
// Libraries: SparkFun MAX3010x Sensor Library; Arduino Wire, SPI, and SD (built in).
// MAX30102 configured for 100 Hz, red + IR, 18-bit ADC; MPU6050: ±2 g, ±250 dps.
// USB emits newline-delimited raw JSON; BLE sends 1 Hz compact telemetry summaries. No AI model is run here.

#include <Arduino.h>  // EN: Import Arduino runtime APIs and data types. TH: ดึง API พื้นฐานของ Arduino และชนิดข้อมูล
#include <stdio.h>  // EN: Provide bounded snprintf for complete CSV row formatting. TH: ใช้ snprintf ที่จำกัดขนาดเพื่อสร้าง CSV row ให้ครบ
#include <string.h>  // EN: Provide memcpy for BLE frame construction. TH: ใช้ memcpy สร้าง BLE frame
#include <Wire.h>  // EN: Communicate with both sensors over I2C. TH: ใช้สื่อสารบัส I2C กับ sensor ทั้งสอง
#include <SPI.h>  // EN: Drive the PCB's dedicated microSD SPI bus. TH: ใช้บัส SPI ของ microSD บน PCB
#include <SD.h>  // EN: Store raw sensor records on a FAT-formatted microSD card. TH: บันทึกข้อมูล sensor ดิบลง microSD ระบบ FAT
#include <freertos/FreeRTOS.h>  // EN: Provide the bounded queue and logger task primitives. TH: ใช้ primitive สำหรับคิวจำกัดขนาดและ task บันทึกข้อมูล
#include <freertos/queue.h>  // EN: Queue records so card writes do not block sensor acquisition. TH: ใช้คิวแยก record เพื่อไม่ให้การเขียนการ์ดขวางการอ่าน sensor
#include <freertos/task.h>  // EN: Run the SD writer independently from the acquisition loop. TH: รันตัวเขียน SD แยกจาก loop อ่าน sensor
#include <MAX30105.h>  // EN: Read the MAX30102 FIFO through SparkFun's MAX3010x library. TH: ใช้ไลบรารี SparkFun MAX3010x อ่าน FIFO ของ MAX30102
#include <BLEDevice.h>  // EN: Provide the ESP32 BLE GATT peripheral. TH: เปิด BLE GATT peripheral ของ ESP32
#include <BLEServer.h>  // EN: Create a connectable BLE server. TH: สร้าง BLE server ให้แอปเชื่อมต่อ
#include "esp_timer.h"  // EN: Read the ESP32 monotonic timer in microseconds. TH: ใช้ตัวนับเวลา monotonic ของ ESP32 เป็น timestamp หน่วยไมโครวินาที

namespace {  // EN: Keep firmware implementation symbols private to this translation unit. TH: จำกัด symbol ภายในไฟล์นี้ไม่ให้ชนกับไฟล์อื่น
constexpr uint8_t MPU6050_ADDR = 0x68;  // EN: Use address 0x68 when the MPU6050 AD0 pin is LOW. TH: ใช้ I2C address 0x68 เมื่อขา AD0 ของ MPU6050 ต่อ LOW
constexpr uint8_t MPU6050_REG_PWR_MGMT_1 = 0x6B;  // EN: Select the register that wakes the MPU6050 from sleep. TH: เลือกรีจิสเตอร์ปลุก MPU6050 จาก sleep
constexpr uint8_t MPU6050_REG_WHO_AM_I = 0x75;  // EN: Select the MPU6050 identity register. TH: เลือกรีจิสเตอร์ระบุตัวตน MPU6050
constexpr uint8_t MPU6050_REG_ACCEL_CONFIG = 0x1C;  // EN: Select the accelerometer full-scale configuration register. TH: เลือกรีจิสเตอร์กำหนดช่วง accelerometer
constexpr uint8_t MPU6050_REG_GYRO_CONFIG = 0x1B;  // EN: Select the gyroscope full-scale configuration register. TH: เลือกรีจิสเตอร์กำหนดช่วง gyroscope
constexpr uint8_t MPU6050_REG_ACCEL_XOUT_H = 0x3B;  // EN: Start the contiguous accel, temperature, and gyro register read. TH: จุดเริ่มอ่าน accelerometer, temperature และ gyroscope ต่อเนื่องกัน
constexpr uint8_t MAX30102_ADDR = 0x57;  // EN: Use the MAX30102's 7-bit I2C address. TH: ใช้ I2C address 7-bit ของ MAX30102
constexpr uint8_t MAX30102_REG_FIFO_OVERFLOW = 0x05;  // EN: Select the MAX30102 FIFO overflow counter register. TH: เลือกรีจิสเตอร์นับ FIFO overflow ของ MAX30102
constexpr uint32_t IMU_PERIOD_US = 20000;  // EN: Target one IMU sample every 20 ms (50 Hz). TH: กำหนดเป้าหมายอ่าน IMU ทุก 20 ms (50 Hz)
constexpr uint32_t PPG_SAMPLE_PERIOD_US = 10000;  // EN: Reconstruct nominal sample intervals for the configured 100 Hz PPG stream. TH: สร้างช่วงเวลาตัวอย่างตาม nominal 100 Hz ที่ตั้งไว้
constexpr uint16_t I2C_TIMEOUT_MS = 10;  // EN: Bound a stuck sensor-bus transaction; verify margin on the real board. TH: จำกัดเวลาธุรกรรม I2C เมื่อบัสค้าง และตรวจ margin บนบอร์ดจริง
constexpr int8_t SD_SCK_PIN = 12;  // EN: Match the checked PCB net SD_SCK to ESP32-S3 GPIO12. TH: ให้ตรงกับ net SD_SCK บน PCB ที่ต่อ ESP32-S3 GPIO12
constexpr int8_t SD_MOSI_PIN = 13;  // EN: Match the checked PCB net SD_MOSI to ESP32-S3 GPIO13. TH: ให้ตรงกับ net SD_MOSI บน PCB ที่ต่อ ESP32-S3 GPIO13
constexpr int8_t SD_MISO_PIN = 14;  // EN: Match the checked PCB net SD_MISO to ESP32-S3 GPIO14. TH: ให้ตรงกับ net SD_MISO บน PCB ที่ต่อ ESP32-S3 GPIO14
constexpr int8_t SD_CS_PIN = 16;  // EN: Match the checked PCB net SD_CS to ESP32-S3 GPIO16. TH: ให้ตรงกับ net SD_CS บน PCB ที่ต่อ ESP32-S3 GPIO16
constexpr int8_t SD_CD_PIN = 15;  // EN: Match the PCB card-detect net to ESP32-S3 GPIO15. TH: ให้ตรงกับ net ตรวจการ์ดบน PCB ที่ต่อ ESP32-S3 GPIO15
constexpr uint32_t SD_SPI_HZ = 10000000;  // EN: Start conservatively at 10 MHz for board bring-up. TH: เริ่ม SPI แบบระมัดระวังที่ 10 MHz สำหรับทดสอบบอร์ด
constexpr UBaseType_t SD_QUEUE_LENGTH = 512;  // EN: Buffer short SD write delays without blocking sensor reads. TH: buffer ช่วงที่ SD เขียนช้าโดยไม่บล็อกการอ่าน sensor
constexpr uint32_t SD_FLUSH_EVERY_RECORDS = 100;  // EN: Bound the interval between durable file flushes. TH: จำกัดช่วงจำนวน record ระหว่างการ flush ลงไฟล์
constexpr char BLE_DEVICE_NAME[] = "Doz-ESP32S3";  // EN: Match the app scanner's device-name filter. TH: ให้ตรงกับตัวกรองชื่ออุปกรณ์ในแอป
constexpr char BLE_SERVICE_UUID[] = "6b2f0001-4f2a-4c3e-9a1b-9d5e7c1a0001";  // EN: Shared telemetry GATT service UUID. TH: UUID GATT service telemetry ที่กำหนดร่วมกับแอป
constexpr char BLE_LIVE_UUID[] = "6b2f0002-4f2a-4c3e-9a1b-9d5e7c1a0001";  // EN: Shared live notification UUID. TH: UUID characteristic แจ้งข้อมูลสดให้แอป
constexpr uint32_t BLE_REPORT_PERIOD_US = 1000000;  // EN: Send one short summary per second. TH: ส่งสรุปสั้นทุกหนึ่งวินาที
constexpr size_t BLE_JSON_CAPACITY = 192;  // EN: Bound each queued BLE report to the JSON packet buffer. TH: จำกัด BLE report แต่ละชุดให้เท่ากับ buffer JSON
constexpr UBaseType_t BLE_TX_QUEUE_LENGTH = 2;  // EN: Keep only two reports pending so stale telemetry cannot build up. TH: ค้าง report ได้แค่สองชุดเพื่อไม่สะสม telemetry เก่า
class DozBleServerCallbacks : public BLEServerCallbacks {  // EN: Restore advertising after a phone disconnects. TH: เปิด advertising ใหม่เมื่อโทรศัพท์ตัดการเชื่อมต่อ
  void onDisconnect(BLEServer *server) override {  // EN: Handle a central disconnect event. TH: จัดการเหตุการณ์ที่โทรศัพท์ disconnect
    (void)server;  // EN: The BLE stack owns this server argument. TH: BLE stack เป็นเจ้าของ server argument นี้
    BLEDevice::startAdvertising();  // EN: Allow app discovery and reconnection. TH: ให้แอปค้นหาและเชื่อมต่ออีกครั้ง
  }
};  // EN: Finish reconnect callback declaration. TH: จบ callback การเชื่อมต่อใหม่
MAX30105 ppg;  // EN: Create the SparkFun sensor-library object for MAX30102. TH: สร้างออบเจ็กต์ไลบรารีสำหรับอ่าน MAX30102
uint64_t nextImuUs = 0;  // EN: Store the next scheduled MPU6050 read time. TH: เก็บกำหนดเวลาที่ควรอ่าน MPU6050 รอบถัดไป
uint64_t nextBleUs = 0;  // EN: Schedule the next BLE report. TH: กำหนดเวลาส่ง BLE รอบถัดไป
uint64_t nextPpgTimestampUs = 0;  // EN: Track the reconstructed timestamp for the next FIFO sample. TH: เก็บ timestamp ที่สร้างขึ้นสำหรับตัวอย่าง FIFO ถัดไป
bool ppgTimestampInitialized = false;  // EN: Track whether the PPG sample clock has an initial anchor. TH: ติดตามว่าเริ่มนาฬิกาตัวอย่าง PPG แล้วหรือยัง
uint8_t lastPpgOverflowCounter = 0;  // EN: Track the hardware overflow counter across FIFO reads. TH: เก็บค่า overflow counter ก่อนหน้าไว้เทียบรอบ
uint32_t pendingPpgLostSamples = 0;  // EN: Carry known dropped samples to the next emitted PPG record. TH: ส่งต่อจำนวนตัวอย่างที่หายไปกับ PPG record ถัดไป
bool ppgReady = false;  // EN: Track successful MAX30102 initialization. TH: สถานะว่าเริ่มต้น MAX30102 สำเร็จหรือไม่
bool imuReady = false;  // EN: Track successful MPU6050 setup and reads. TH: สถานะว่าอ่านและตั้งค่า MPU6050 สำเร็จหรือไม่
BLECharacteristic *liveCharacteristic = nullptr;  // EN: Store the live telemetry characteristic. TH: เก็บ characteristic สำหรับ telemetry สด
BLEServer *bleServer = nullptr;  // EN: Track whether any app client is connected. TH: ตรวจว่ามีแอปเชื่อมต่ออยู่หรือไม่
struct BlePacket {  // EN: Hold one bounded BLE report for the transmitter task. TH: เก็บ BLE report หนึ่งชุดที่มีขนาดจำกัดสำหรับ task ส่งข้อมูล
  uint16_t length;  // EN: Store the exact number of JSON bytes to transmit. TH: เก็บจำนวน byte JSON ที่ต้องส่งจริง
  char payload[BLE_JSON_CAPACITY];  // EN: Copy the complete JSON report into queue-owned storage. TH: คัดลอก JSON report ครบชุดไว้ในหน่วยความจำของคิว
};  // EN: Finish the fixed-size BLE queue item. TH: จบโครงสร้าง queue item BLE ขนาดคงที่
QueueHandle_t bleTxQueue = nullptr;  // EN: Hold the nonblocking BLE transmission queue. TH: เก็บคิวส่ง BLE แบบไม่บล็อก
uint32_t bleTxQueueDrops = 0;  // EN: Count reports skipped when the BLE queue is full. TH: นับ report ที่ข้ามเมื่อคิว BLE เต็ม
void notifyJsonFragments(const char *payload, size_t length);  // EN: Declare the bounded fragment sender used by the worker task. TH: ประกาศตัวส่ง fragment แบบจำกัดขนาดที่ worker task ใช้
void bleTransmitTask(void *argument);  // EN: Declare the background BLE sender before server setup. TH: ประกาศ task ส่ง BLE ก่อนเริ่มตั้ง server
uint64_t redSum = 0, irSum = 0;  // EN: Accumulate PPG counts over each report interval. TH: สะสมค่า PPG ในแต่ละช่วงรายงาน
int64_t axSum = 0, aySum = 0, azSum = 0, gxSum = 0, gySum = 0, gzSum = 0;  // EN: Accumulate signed IMU counts. TH: สะสม raw count แบบ signed จาก IMU
uint32_t ppgCount = 0, imuCount = 0;  // EN: Count samples for interval means. TH: นับจำนวน sample เพื่อคำนวณค่าเฉลี่ย
uint16_t bleSequence = 0;  // EN: Identify BLE fragments belonging to one JSON report. TH: ระบุลำดับ fragment ของ JSON report เดียวกัน
enum class RecordType : uint8_t { Ppg = 1, Imu = 2 };  // EN: Distinguish optical and inertial samples in the unified CSV. TH: แยก sample แสงกับ IMU ใน CSV รวม
struct RawRecord {  // EN: Hold one fixed-size raw sample for the SD writer queue. TH: เก็บ sample ดิบหนึ่งชุดในคิวตัวเขียน SD
  uint64_t timestampUs;  // EN: Store the monotonic timestamp in microseconds. TH: เก็บ timestamp monotonic หน่วยไมโครวินาที
  uint32_t sequence;  // EN: Detect dropped SD queue records by sequence gaps. TH: ตรวจ record ที่ตกหล่นจากช่องว่างของ sequence
  uint32_t ppgSampleIndex;  // EN: Preserve the PPG-only sample position. TH: เก็บตำแหน่ง sample เฉพาะ PPG
  uint32_t lostSamples;  // EN: Store MAX30102 FIFO overflow count for PPG records. TH: เก็บจำนวน FIFO overflow ของ MAX30102 ใน record PPG
  uint32_t red;  // EN: Store the raw MAX30102 red ADC count. TH: เก็บ ADC count ดิบ Red จาก MAX30102
  uint32_t ir;  // EN: Store the raw MAX30102 infrared ADC count. TH: เก็บ ADC count ดิบ IR จาก MAX30102
  int16_t ax, ay, az;  // EN: Store signed MPU6050 accelerometer counts. TH: เก็บ signed count accelerometer จาก MPU6050
  int16_t gx, gy, gz;  // EN: Store signed MPU6050 gyroscope counts. TH: เก็บ signed count gyroscope จาก MPU6050
  int16_t temp;  // EN: Store the MPU6050 die-temperature raw count. TH: เก็บ raw count อุณหภูมิภายในชิป MPU6050
  RecordType type;  // EN: Mark which sensor produced this row. TH: ระบุชนิด sensor ที่สร้างแถวข้อมูลนี้
};  // EN: Finish the fixed-width queue record. TH: จบโครงสร้าง queue record ขนาดคงที่
SPIClass sdSpi(FSPI);  // EN: Create a separate SPI controller for microSD on ESP32-S3. TH: สร้าง SPI controller แยกสำหรับ microSD บน ESP32-S3
QueueHandle_t sdQueue = nullptr;  // EN: Hold the bounded SD writer queue handle. TH: เก็บ handle ของคิวเขียน SD แบบจำกัดขนาด
volatile bool sdReady = false;  // EN: Publish card readiness between setup/logger and acquisition code. TH: ส่งสถานะความพร้อมของการ์ดระหว่าง setup/logger กับ acquisition
uint32_t recordSequence = 0;  // EN: Number every sample record, including samples rejected by a full queue. TH: กำหนดเลขทุก sample รวมถึง sample ที่คิวเต็มจนรับไม่ได้
uint32_t nextPpgSampleIndex = 0;  // EN: Keep PPG indexes independent from interleaved IMU and SD records. TH: แยก PPG index จาก record IMU และ SD ที่แทรกกัน
uint32_t sdQueueDrops = 0;  // EN: Count records lost because the SD queue was full. TH: นับ record ที่หายเพราะคิว SD เต็ม
char sdFilePath[16] = {0};  // EN: Hold the short FAT-compatible per-boot filename. TH: เก็บชื่อไฟล์ต่อการเปิดเครื่องที่เข้ากับข้อจำกัด FAT
bool sdFailureReported = false;  // EN: Prevent repeated SD failure messages on the USB stream. TH: ป้องกันการส่งข้อความ SD error ซ้ำถี่ทาง USB

void status(const char *message) {  // EN: Emit a small status record for the host parser. TH: ส่ง status record สั้นให้ host parser
  Serial.print("{\"type\":\"status\",\"message\":\"");  // EN: Open the JSON status object and message field. TH: เริ่ม JSON status object และ field message
  Serial.print(message);  // EN: Write a fixed internal status code. TH: เขียนรหัสสถานะที่กำหนดไว้ภายใน
  Serial.println("\"}");  // EN: Close the JSON object and terminate the JSONL record. TH: ปิด JSON object และจบบรรทัด JSONL
}

bool enqueueRecord(const RawRecord &record) {  // EN: Add a record without waiting for slow flash-card I/O. TH: เพิ่ม record โดยไม่รอ I/O ของการ์ดที่อาจช้า
  if (sdQueue == nullptr || !sdReady) return false;  // EN: Reject logging when queue/card setup failed. TH: ปฏิเสธการ log เมื่อคิวหรือการ์ดไม่พร้อม
  RawRecord queued = record;  // EN: Copy the sample so the queue owns a stable snapshot. TH: คัดลอก sample ให้คิวถือ snapshot ที่คงที่
  queued.sequence = ++recordSequence;  // EN: Assign a sequence before attempting enqueue so drops leave visible gaps. TH: กำหนด sequence ก่อน enqueue เพื่อให้ record ที่ตกหล่นเห็นเป็นช่องว่าง
  if (xQueueSendToBack(sdQueue, &queued, 0) != pdTRUE) {  // EN: Never block sensor acquisition when the bounded queue is full. TH: ห้ามบล็อกการอ่าน sensor เมื่อคิวจำกัดขนาดเต็ม
    ++sdQueueDrops;  // EN: Track the record loss for later diagnostics. TH: นับ record ที่หายไว้ตรวจสอบภายหลัง
    return false;  // EN: Report the queue overflow to the caller. TH: แจ้งผู้เรียกว่าคิวล้น
  }  // EN: Finish the nonblocking queue insertion. TH: จบการเพิ่มข้อมูลลงคิวแบบไม่บล็อก
  return true;  // EN: Confirm that the writer queue accepted the record. TH: ยืนยันว่าคิวตัวเขียนรับ record แล้ว
}  // EN: Finish nonblocking record enqueue. TH: จบฟังก์ชัน enqueue แบบไม่บล็อก

bool writeRecordCsv(File &file, const RawRecord &record) {  // EN: Serialize one typed sensor sample and verify the complete write. TH: แปลง sample sensor หนึ่งชุดและตรวจว่าเขียนครบ
  char line[128];  // EN: Bound temporary CSV row memory and reject unexpected formatting growth. TH: จำกัดหน่วยความจำของ CSV row และปฏิเสธกรณีข้อความยาวผิดคาด
  int length = 0;  // EN: Store the number of formatted bytes excluding the null terminator. TH: เก็บจำนวน byte ที่ format แล้วโดยไม่รวม null terminator
  if (record.type == RecordType::Ppg) {  // EN: Write PPG rows with optical counts and overflow metadata. TH: เขียนแถว PPG พร้อม optical count และ metadata overflow
    length = snprintf(line, sizeof(line), "ppg,%lu,%lu,%llu,%lu,%lu,%lu,,,,,,,\n", static_cast<unsigned long>(record.sequence), static_cast<unsigned long>(record.ppgSampleIndex), static_cast<unsigned long long>(record.timestampUs), static_cast<unsigned long>(record.lostSamples), static_cast<unsigned long>(record.red), static_cast<unsigned long>(record.ir));  // EN: Leave IMU-only columns empty rather than fabricating values. TH: เว้นคอลัมน์เฉพาะ IMU ว่างโดยไม่สร้างค่าเทียม
  } else {  // EN: Write IMU rows with signed inertial counts. TH: เขียนแถว IMU พร้อม signed inertial count
    length = snprintf(line, sizeof(line), "imu,%lu,,%llu,0,,,%d,%d,%d,%d,%d,%d,%d\n", static_cast<unsigned long>(record.sequence), static_cast<unsigned long long>(record.timestampUs), record.ax, record.ay, record.az, record.gx, record.gy, record.gz, record.temp);  // EN: Preserve raw signed register counts without unit conversion. TH: เก็บ signed register count ดิบโดยไม่แปลงหน่วย
  }  // EN: Finish sensor-specific CSV serialization. TH: จบการ serialize CSV ตามชนิด sensor
  if (length <= 0 || static_cast<size_t>(length) >= sizeof(line)) return false;  // EN: Reject formatting errors or truncation before touching the SD file. TH: ปฏิเสธ format error หรือข้อความถูกตัดก่อนเขียน SD
  return file.write(reinterpret_cast<const uint8_t *>(line), static_cast<size_t>(length)) == static_cast<size_t>(length);  // EN: Accept only an exact full-row write; TH: ยอมรับเฉพาะเมื่อเขียน row ครบทุก byte
}  // EN: Finish one CSV row writer. TH: จบตัวเขียนแถว CSV หนึ่งแถว

void sdWriterTask(void *argument) {  // EN: Drain the sample queue on a lower-priority background task. TH: อ่านคิว sample ด้วย background task ที่ priority ต่ำกว่า
  (void)argument;  // EN: This task does not need an argument. TH: task นี้ไม่ต้องใช้ argument
  File file = SD.open(sdFilePath, FILE_APPEND);  // EN: Open this boot's unique log file for appending. TH: เปิดไฟล์ log เฉพาะรอบเปิดเครื่องเพื่อเขียนต่อท้าย
  if (!file) {  // EN: Detect failure before accepting any SD records. TH: ตรวจความล้มเหลวก่อนรับ record ลง SD
    sdReady = false;  // EN: Disable enqueue after an open failure. TH: ปิดการ enqueue เมื่อเปิดไฟล์ไม่สำเร็จ
    vTaskDelete(nullptr);  // EN: Stop this writer task cleanly. TH: จบ writer task อย่างเรียบร้อย
  }  // EN: Finish initial log-file validation. TH: จบการตรวจไฟล์ log ตอนเริ่ม
  RawRecord record;  // EN: Reserve one queue item for each writer iteration. TH: เตรียมพื้นที่สำหรับ queue item ในแต่ละรอบเขียน
  uint32_t pendingFlush = 0;  // EN: Count successful rows since the last durable flush. TH: นับจำนวนแถวที่เขียนตั้งแต่ flush ล่าสุด
  for (;;) {  // EN: Keep the logger available for the lifetime of the device. TH: ให้ logger ทำงานตลอดอายุการเปิดอุปกรณ์
    if (xQueueReceive(sdQueue, &record, pdMS_TO_TICKS(250)) == pdTRUE) {  // EN: Wait briefly for work without spinning. TH: รอข้อมูลช่วงสั้นโดยไม่หมุน loop เปลือง CPU
      const bool rowWritten = writeRecordCsv(file, record);  // EN: Write and verify every byte of this raw sensor row. TH: เขียนและตรวจทุก byte ของแถว sensor ดิบ
      if (!rowWritten || file.getWriteError()) {  // EN: Treat short rows and filesystem write errors as card failure. TH: ถือแถวเขียนไม่ครบหรือ filesystem error เป็นความล้มเหลวของการ์ด
        sdReady = false;  // EN: Stop accepting new records when media writes fail. TH: หยุดรับ record ใหม่เมื่อเขียนสื่อบันทึกล้มเหลว
        file.close();  // EN: Release the failed file handle. TH: ปิด file handle ที่ล้มเหลว
        vTaskDelete(nullptr);  // EN: Stop this writer rather than looping on a broken card. TH: จบ writer แทนการวนซ้ำบนการ์ดที่เสีย
      }  // EN: Finish write-integrity validation. TH: จบการตรวจความสมบูรณ์ของการเขียน
      ++pendingFlush;  // EN: Count this accepted CSV row. TH: นับ CSV row ที่รับและเขียนแล้ว
    }  // EN: Finish queue receive handling. TH: จบการจัดการ queue receive
    if (pendingFlush >= SD_FLUSH_EVERY_RECORDS || (pendingFlush > 0 && uxQueueMessagesWaiting(sdQueue) == 0)) {  // EN: Flush in batches and whenever the queue becomes idle. TH: flush เป็นชุดและเมื่อคิวว่าง
      file.flush();  // EN: Commit buffered filesystem data to the card. TH: commit ข้อมูล filesystem ที่ buffer ไว้ลงการ์ด
      if (file.getWriteError()) {  // EN: Detect a flush failure before continuing. TH: ตรวจ flush failure ก่อนทำต่อ
        sdReady = false;  // EN: Mark logging unavailable after a durability error. TH: ระบุว่า log ใช้ไม่ได้เมื่อ commit ข้อมูลล้มเหลว
        file.close();  // EN: Release the failed file handle. TH: ปิด file handle ที่ล้มเหลว
        vTaskDelete(nullptr);  // EN: Stop the writer after failed commit. TH: จบ writer หลัง commit ไม่สำเร็จ
      }  // EN: Finish flush error handling. TH: จบการจัดการ flush error
      pendingFlush = 0;  // EN: Start a new flush batch. TH: เริ่มนับชุด flush รอบใหม่
    }  // EN: Finish periodic durability handling. TH: จบการจัดการความคงทนของข้อมูลตามรอบ
  }  // EN: Finish the forever-running logger loop. TH: จบ loop logger ที่ทำงานต่อเนื่อง
}  // EN: Finish the SD background task. TH: จบ SD background task

void startSdLogger() {  // EN: Mount the card without formatting and start the asynchronous writer. TH: mount การ์ดโดยไม่ format และเริ่มตัวเขียนแบบ asynchronous
  if (digitalRead(SD_CD_PIN) != LOW) {  // EN: The Hirose switch is open without a card and closes to GND when inserted. TH: สวิตช์ Hirose เปิดเมื่อไม่มีการ์ดและต่อ GND เมื่อใส่การ์ด
    status("sd_card_not_inserted");  // EN: Report absent media without attempting an SPI mount. TH: แจ้งว่าไม่มีการ์ดโดยไม่พยายาม mount ผ่าน SPI
    return;  // EN: Preserve USB/BLE sensor streaming when optional storage is absent. TH: คงการสตรีม sensor ทาง USB/BLE เมื่อไม่มี storage เสริม
  }  // EN: Finish the active-low card-detect check. TH: จบการตรวจ card-detect แบบ active-low
  sdQueue = xQueueCreate(SD_QUEUE_LENGTH, sizeof(RawRecord));  // EN: Allocate the bounded queue before starting acquisition. TH: จองคิวจำกัดขนาดก่อนเริ่มอ่าน sensor
  if (sdQueue == nullptr) {  // EN: Detect insufficient RAM for the SD queue. TH: ตรวจ RAM ไม่พอสำหรับคิว SD
    status("sd_queue_allocation_failed");  // EN: Report the queue allocation failure over USB. TH: รายงานคิวจองหน่วยความจำไม่สำเร็จทาง USB
    return;  // EN: Keep sensor USB/BLE streaming available without SD. TH: คงการสตรีม sensor ทาง USB/BLE แม้ไม่มี SD
  }  // EN: Finish queue allocation check. TH: จบการตรวจการจองคิว
  sdSpi.begin(SD_SCK_PIN, SD_MISO_PIN, SD_MOSI_PIN, SD_CS_PIN);  // EN: Route the dedicated SPI controller to PCB-mapped pins. TH: กำหนดขา SPI ให้ตรง pin map ของ PCB
  if (!SD.begin(SD_CS_PIN, sdSpi, SD_SPI_HZ)) {  // EN: Mount the card at a conservative clock and never auto-format it. TH: mount การ์ดที่ clock ระมัดระวังและไม่สั่ง format อัตโนมัติ
    status("sd_mount_failed; check_card_format_wiring_and_power");  // EN: Explain likely mount prerequisites without disabling USB/BLE. TH: แจ้งสิ่งที่ควรตรวจโดยไม่ปิด USB/BLE
    return;  // EN: Continue device operation without local storage. TH: ให้อุปกรณ์ทำงานต่อโดยไม่มี local storage
  }  // EN: Finish card-mount validation. TH: จบการตรวจการ mount การ์ด
  for (uint16_t run = 1; run <= 9999; ++run) {  // EN: Find an unused short filename without overwriting previous sessions. TH: หา filename สั้นที่ยังไม่ใช้เพื่อไม่เขียนทับ session เก่า
    snprintf(sdFilePath, sizeof(sdFilePath), "/R%04u.CSV", run);  // EN: Use an 8.3-compatible per-session filename. TH: ใช้ชื่อไฟล์ต่อ session ตามรูปแบบ 8.3
    if (!SD.exists(sdFilePath)) break;  // EN: Keep the first free filename. TH: ใช้ filename ว่างตัวแรก
    sdFilePath[0] = '\0';  // EN: Clear the candidate before checking the next name. TH: ล้างชื่อ candidate ก่อนตรวจชื่อถัดไป
  }  // EN: Finish unique filename search. TH: จบการค้นหา filename ไม่ซ้ำ
  if (sdFilePath[0] == '\0') {  // EN: Refuse to overwrite files when the name space is exhausted. TH: ปฏิเสธการเขียนทับเมื่อชื่อไฟล์เต็มช่วง
    sdReady = false;  // EN: Keep the queue disabled on filename exhaustion. TH: ปิดคิวเมื่อหา filename ใหม่ไม่ได้
    status("sd_filename_space_exhausted");  // EN: Report that the card needs archival or cleanup. TH: แจ้งว่าต้องสำรองหรือล้างไฟล์ในการ์ด
    return;  // EN: Preserve existing data and continue USB/BLE streaming. TH: รักษาข้อมูลเดิมและสตรีม USB/BLE ต่อ
  }  // EN: Finish filename-space guard. TH: จบการป้องกันชื่อไฟล์เต็ม
  File header = SD.open(sdFilePath, FILE_WRITE);  // EN: Create the new session file exclusively after confirming it does not exist. TH: สร้างไฟล์ session ใหม่หลังยืนยันว่าไม่มีไฟล์เดิม
  if (!header) {  // EN: Detect failure to create the session log. TH: ตรวจสร้างไฟล์ session log ไม่สำเร็จ
    status("sd_log_create_failed");  // EN: Report file-creation failure. TH: รายงานสร้างไฟล์ไม่สำเร็จ
    return;  // EN: Preserve USB/BLE streaming without local logging. TH: คง USB/BLE โดยไม่บันทึกในเครื่อง
  }  // EN: Finish initial file creation check. TH: จบการตรวจสร้างไฟล์เริ่มต้น
  header.println("type,sequence,ppg_sample_index,timestamp_us,lost_samples,red_raw,ir_raw,ax_raw,ay_raw,az_raw,gx_raw,gy_raw,gz_raw,temp_raw");  // EN: Write a schema that keeps sensor-native raw counts and asynchronous timestamps. TH: เขียน schema ที่รักษา raw count ของ sensor และ timestamp ที่แต่ละ sensor ไม่ตรงกัน
  header.flush();  // EN: Commit the header before acquisition begins. TH: commit header ก่อนเริ่มเก็บข้อมูล
  const bool headerOk = !header.getWriteError();  // EN: Verify that the schema header reached the filesystem. TH: ตรวจว่า schema header ถูกเขียนถึง filesystem
  header.close();  // EN: Close the header handle before the logger task opens the file. TH: ปิด handle header ก่อน logger task เปิดไฟล์
  if (!headerOk) {  // EN: Reject a session whose schema could not be committed. TH: ปฏิเสธ session ที่ commit schema ไม่สำเร็จ
    status("sd_header_write_failed");  // EN: Report the header write error. TH: รายงานเขียน header ไม่สำเร็จ
    return;  // EN: Do not start writing rows with an invalid schema. TH: ไม่เริ่มเขียนแถวเมื่อ schema ใช้ไม่ได้
  }  // EN: Finish header integrity validation. TH: จบการตรวจความถูกต้อง header
  sdReady = true;  // EN: Allow sensor records into the queue. TH: อนุญาตให้ส่ง record sensor ลงคิว
  if (xTaskCreate(sdWriterTask, "sd_writer", 4096, nullptr, 1, nullptr) != pdPASS) {  // EN: Start a small low-priority task for card writes. TH: เริ่ม task priority ต่ำสำหรับเขียนการ์ด
    sdReady = false;  // EN: Disable logging if the task could not be created. TH: ปิดการ log หากสร้าง task ไม่สำเร็จ
    status("sd_writer_task_start_failed");  // EN: Report task creation failure. TH: รายงานสร้าง task ไม่สำเร็จ
    return;  // EN: Keep acquisition active without SD logging. TH: คงการเก็บข้อมูลต่อโดยไม่ log SD
  }  // EN: Finish writer-task startup validation. TH: จบการตรวจเริ่ม writer task
  status("sd_ready; raw_log_started");  // EN: Confirm the filename and active raw logger. TH: ยืนยัน filename และเริ่ม logger raw แล้ว
}  // EN: Finish SD logger startup. TH: จบการเริ่ม SD logger

bool writeMpuRegister(uint8_t reg, uint8_t value) {  // EN: Write one MPU6050 configuration register. TH: เขียนค่าลง configuration register ของ MPU6050 หนึ่งตัว
  Wire.beginTransmission(MPU6050_ADDR);  // EN: Start an I2C write to the MPU6050. TH: เริ่มส่งข้อมูล I2C ไปยัง MPU6050
  Wire.write(reg);  // EN: Select the target register address. TH: ระบุ address ของรีจิสเตอร์ปลายทาง
  Wire.write(value);  // EN: Queue the byte to write into that register. TH: เตรียม byte ที่จะเขียนลงรีจิสเตอร์
  return Wire.endTransmission() == 0;  // EN: Return true only when the I2C write is acknowledged. TH: คืน true เมื่อการเขียน I2C ได้รับการตอบรับ
}

bool readMpuRegister(uint8_t reg, uint8_t &value) {  // EN: Read one MPU6050 register and validate the I2C response. TH: อ่านรีจิสเตอร์ MPU6050 หนึ่งตัวและตรวจ response I2C
  Wire.beginTransmission(MPU6050_ADDR);  // EN: Begin the register-address write phase. TH: เริ่มช่วงส่ง address ของรีจิสเตอร์
  Wire.write(reg);  // EN: Select the requested register. TH: เลือกรีจิสเตอร์ที่ต้องการ
  if (Wire.endTransmission(false) != 0 || Wire.requestFrom(MPU6050_ADDR, static_cast<uint8_t>(1), static_cast<uint8_t>(true)) != 1) {  // EN: Require an acknowledged address and exactly one returned byte. TH: บังคับให้ address ได้รับการตอบรับและมี byte กลับมาครบหนึ่งตัว
    return false;  // EN: Reject a failed or incomplete register read. TH: ปฏิเสธการอ่านรีจิสเตอร์ที่ล้มเหลวหรือได้ข้อมูลไม่ครบ
  }  // EN: Finish validating the I2C read length. TH: จบการตรวจความยาวข้อมูล I2C
  const int rawValue = Wire.read();  // EN: Read the byte from the receive buffer. TH: อ่าน byte จาก receive buffer
  if (rawValue < 0) {  // EN: Defend against an unexpectedly empty receive buffer. TH: ป้องกันกรณี receive buffer ว่างผิดปกติ
    return false;  // EN: Do not use a missing register value. TH: ไม่ใช้ค่ารีจิสเตอร์ที่อ่านไม่ได้
  }  // EN: Finish checking the receive-buffer result. TH: จบการตรวจผลจาก receive buffer
  value = static_cast<uint8_t>(rawValue);  // EN: Store the validated register byte. TH: เก็บ byte ของรีจิสเตอร์ที่ตรวจแล้ว
  return true;  // EN: Report a complete register read. TH: แจ้งว่าอ่านรีจิสเตอร์ครบ
}  // EN: Finish the bounded MPU6050 register reader. TH: จบฟังก์ชันอ่านรีจิสเตอร์ MPU6050 แบบตรวจขอบเขต

int16_t readSigned16() {  // EN: Read two queued I2C bytes as one signed 16-bit count. TH: อ่าน I2C สอง byte เป็น count signed 16-bit หนึ่งค่า
  uint16_t high = static_cast<uint16_t>(Wire.read());  // EN: Read the high-order byte. TH: อ่าน byte ลำดับสูง
  uint16_t low = static_cast<uint16_t>(Wire.read());  // EN: Read the low-order byte. TH: อ่าน byte ลำดับต่ำ
  return static_cast<int16_t>((high << 8) | low);  // EN: Join the bytes and interpret two's-complement sign. TH: รวม byte แล้วตีความเครื่องหมายแบบ two's complement
}

bool readPpgOverflowCounter(uint8_t &counter) {  // EN: Read the hardware FIFO overflow counter without draining sensor samples. TH: อ่าน FIFO overflow counter โดยไม่ดึงตัวอย่าง sensor
  Wire.beginTransmission(MAX30102_ADDR);  // EN: Begin the MAX30102 register-read transaction. TH: เริ่ม transaction อ่านรีจิสเตอร์ MAX30102
  Wire.write(MAX30102_REG_FIFO_OVERFLOW);  // EN: Select the overflow counter register. TH: เลือกรีจิสเตอร์ overflow counter
  if (Wire.endTransmission(false) != 0 || Wire.requestFrom(MAX30102_ADDR, static_cast<uint8_t>(1), static_cast<uint8_t>(true)) != 1) {  // EN: Require a successful address phase and exactly one returned byte. TH: บังคับให้เลือก address สำเร็จและได้ byte กลับมาครบหนึ่งตัว
    return false;  // EN: Do not trust an incomplete counter read. TH: ไม่เชื่อค่าที่อ่าน counter ไม่ครบ
  }  // EN: Finish the I2C transfer validation. TH: จบการตรวจ I2C transfer
  const int value = Wire.read();  // EN: Read the returned counter byte. TH: อ่าน byte counter ที่ส่งกลับ
  if (value < 0) {  // EN: Guard against an empty Wire receive buffer. TH: ป้องกัน receive buffer ของ Wire ว่าง
    return false;  // EN: Reject an unavailable register value. TH: ปฏิเสธเมื่อไม่มีค่าจากรีจิสเตอร์
  }  // EN: Finish the empty-buffer check. TH: จบการตรวจ buffer ว่าง
  counter = static_cast<uint8_t>(value & 0x1F);  // EN: Keep the five-bit hardware overflow count. TH: เก็บเฉพาะ overflow count ห้า bit ของ hardware
  return true;  // EN: Report a complete counter read. TH: แจ้งว่าอ่าน counter ครบ
}  // EN: Finish the overflow-counter reader. TH: จบฟังก์ชันอ่าน overflow counter

void emitPpg(uint64_t timestampUs, uint32_t lostSamples) {  // EN: Emit one FIFO sample with reconstructed time and loss metadata. TH: ส่ง FIFO sample หนึ่งชุดพร้อมเวลาโดยประมาณและจำนวนตัวอย่างที่หาย
  if (lostSamples > UINT32_MAX - nextPpgSampleIndex || nextPpgSampleIndex + lostSamples == UINT32_MAX) {  // EN: Stop before the PPG-only index wraps. TH: หยุดก่อน index เฉพาะ PPG ล้น
    status("ppg_sample_index_exhausted");  // EN: Report an exhausted index instead of emitting ambiguous samples. TH: แจ้ง index เต็มแทนการส่ง sample ที่ตำแหน่งกำกวม
    ppgReady = false;  // EN: Disable further PPG reads until reboot. TH: ปิดการอ่าน PPG ต่อจนกว่าจะ reboot
    return;  // EN: Do not log an invalid sample. TH: ไม่บันทึก sample ที่ index ผิด
  }  // EN: Finish the PPG index overflow guard. TH: จบการป้องกัน index PPG ล้น
  nextPpgSampleIndex += lostSamples;  // EN: Encode known FIFO loss as an index gap. TH: แสดง FIFO loss ที่ทราบเป็นช่องว่าง index
  const uint32_t sampleIndex = nextPpgSampleIndex++;  // EN: Assign the next PPG-specific sample index. TH: กำหนด index เฉพาะให้ PPG sample ถัดไป
  const uint32_t red = ppg.getFIFORed();  // EN: Read the oldest queued raw red ADC count. TH: อ่าน ADC count ดิบ Red ที่เก่าสุดในคิว
  const uint32_t ir = ppg.getFIFOIR();  // EN: Read the matching oldest queued raw IR ADC count. TH: อ่าน ADC count ดิบ IR ที่คู่กับตัวอย่างเก่าสุด
  redSum += red;  // EN: Add red count to the current BLE interval. TH: สะสมค่า Red ในช่วง BLE ปัจจุบัน
  irSum += ir;  // EN: Add IR count to the current BLE interval. TH: สะสมค่า IR ในช่วง BLE ปัจจุบัน
  ++ppgCount;  // EN: Count this PPG sample. TH: นับ sample PPG นี้
  RawRecord record = {};  // EN: Initialize an optical-only record with zeroed unused fields. TH: เริ่ม record แสงและกำหนดช่องที่ไม่ได้ใช้เป็นศูนย์
  record.timestampUs = timestampUs;  // EN: Preserve the reconstructed PPG sample timestamp. TH: เก็บ timestamp PPG ที่สร้างจาก FIFO cadence
  record.ppgSampleIndex = sampleIndex;  // EN: Keep PPG indexing separate from the SD record sequence. TH: แยก PPG index ออกจาก sequence ของ record SD
  record.lostSamples = lostSamples;  // EN: Preserve the hardware FIFO loss count. TH: เก็บจำนวน sample ที่ FIFO แจ้งว่าหาย
  record.red = red;  // EN: Store the raw red ADC count. TH: เก็บ ADC count ดิบ Red
  record.ir = ir;  // EN: Store the raw infrared ADC count. TH: เก็บ ADC count ดิบ IR
  record.type = RecordType::Ppg;  // EN: Mark this row as an optical sample. TH: ระบุว่าแถวนี้เป็น sample สัญญาณแสง
  enqueueRecord(record);  // EN: Queue the sample without blocking the FIFO drain. TH: ส่ง sample เข้าคิวโดยไม่บล็อกการอ่าน FIFO
  Serial.printf("{\"type\":\"ppg\",\"sample_index\":%lu,\"t_us\":%llu,\"red\":%lu,\"ir\":%lu,\"lost_samples\":%lu}\n",  // EN: Start one raw PPG JSONL record with an explicit sample-loss field. TH: เริ่ม PPG JSONL raw พร้อม field แจ้งจำนวนตัวอย่างที่หาย
                static_cast<unsigned long>(sampleIndex),  // EN: Serialize the PPG-only sample index. TH: serialize index เฉพาะ PPG
                static_cast<unsigned long long>(timestampUs),  // EN: Serialize the 64-bit microsecond timestamp. TH: serialize timestamp ไมโครวินาทีแบบ 64-bit
                static_cast<unsigned long>(red), static_cast<unsigned long>(ir),  // EN: Serialize the raw optical ADC counts. TH: serialize ADC count ดิบของสัญญาณแสง
                static_cast<unsigned long>(lostSamples));  // EN: Serialize the hardware-reported number of dropped samples. TH: serialize จำนวนตัวอย่างที่ hardware แจ้งว่าหาย
}

void emitImu() {  // EN: Read a complete MPU6050 register block and emit raw counts. TH: อ่าน register block ของ MPU6050 ให้ครบแล้วส่ง raw count
  Wire.beginTransmission(MPU6050_ADDR);  // EN: Start the I2C register-selection transaction. TH: เริ่ม transaction I2C เพื่อเลือกรีจิสเตอร์
  Wire.write(MPU6050_REG_ACCEL_XOUT_H);  // EN: Select the first accelerometer output register. TH: เลือกรีจิสเตอร์ output ของ accelerometer ตัวแรก
  if (Wire.endTransmission(false) != 0 || Wire.requestFrom(MPU6050_ADDR, static_cast<uint8_t>(14), static_cast<uint8_t>(true)) != 14) {  // EN: Require a successful register select and all 14 bytes. TH: บังคับให้เลือก register สำเร็จและอ่านครบ 14 byte
    status("mpu6050_read_error");  // EN: Report an incomplete 14-byte I2C block. TH: รายงานเมื่อ I2C อ่านข้อมูลครบ 14 byte ไม่ได้
    return;  // EN: Do not emit values from a partial sensor read. TH: ไม่ส่งค่า sensor ที่อ่านไม่ครบออกไป
  }
  const int16_t ax = readSigned16();  // EN: Read raw X-axis accelerometer count. TH: อ่านค่า accelerometer แกน X แบบ raw count
  const int16_t ay = readSigned16();  // EN: Read raw Y-axis accelerometer count. TH: อ่านค่า accelerometer แกน Y แบบ raw count
  const int16_t az = readSigned16();  // EN: Read raw Z-axis accelerometer count. TH: อ่านค่า accelerometer แกน Z แบบ raw count
  const int16_t temp = readSigned16();  // EN: Read die temperature, not skin temperature. TH: อ่านอุณหภูมิภายในชิป ไม่ใช่อุณหภูมิผิวหนัง
  const int16_t gx = readSigned16();  // EN: Read raw X-axis gyroscope count. TH: อ่านค่า gyroscope แกน X แบบ raw count
  const int16_t gy = readSigned16();  // EN: Read raw Y-axis gyroscope count. TH: อ่านค่า gyroscope แกน Y แบบ raw count
  const int16_t gz = readSigned16();  // EN: Read raw Z-axis gyroscope count. TH: อ่านค่า gyroscope แกน Z แบบ raw count
  axSum += ax; aySum += ay; azSum += az;  // EN: Accumulate accelerometer axes. TH: สะสม accelerometer ทั้งสามแกน
  gxSum += gx; gySum += gy; gzSum += gz;  // EN: Accumulate gyroscope axes. TH: สะสม gyroscope ทั้งสามแกน
  ++imuCount;  // EN: Count this IMU sample. TH: นับ sample IMU นี้
  const uint64_t timestampUs = static_cast<uint64_t>(esp_timer_get_time());  // EN: Timestamp the IMU sample after the complete register read. TH: ประทับเวลา IMU หลังอ่านชุดข้อมูล
  RawRecord record = {};  // EN: Initialize an inertial-only record. TH: เริ่ม record เฉพาะข้อมูล IMU
  record.timestampUs = timestampUs;  // EN: Preserve the IMU read timestamp. TH: เก็บ timestamp ตอนอ่าน IMU
  record.ax = ax; record.ay = ay; record.az = az;  // EN: Store raw accelerometer counts. TH: เก็บ raw count accelerometer
  record.gx = gx; record.gy = gy; record.gz = gz;  // EN: Store raw gyroscope counts. TH: เก็บ raw count gyroscope
  record.temp = temp;  // EN: Store the chip-temperature count without calling it skin temperature. TH: เก็บค่าอุณหภูมิชิปโดยไม่เรียกว่าอุณหภูมิผิว
  record.type = RecordType::Imu;  // EN: Mark this row as an inertial sample. TH: ระบุว่าแถวนี้เป็น sample IMU
  enqueueRecord(record);  // EN: Queue the sample without blocking the acquisition loop. TH: ส่ง sample เข้าคิวโดยไม่บล็อก loop เก็บข้อมูล
  Serial.printf(  // EN: Start a single printf call for one complete IMU JSONL record. TH: เริ่ม printf ครั้งเดียวสำหรับ IMU JSONL หนึ่ง record ที่สมบูรณ์
                "{\"type\":\"imu\",\"t_us\":%llu,\"ax_raw\":%d,\"ay_raw\":%d,\"az_raw\":%d,"  // EN: Begin the JSONL record with timestamp and acceleration fields. TH: เริ่ม JSONL record ด้วย timestamp และ field ความเร่ง
                "\"gx_raw\":%d,\"gy_raw\":%d,\"gz_raw\":%d,\"temp_raw\":%d}\n",  // EN: Append gyroscope/temperature fields and terminate the record. TH: ต่อ field gyroscope/temperature และปิด record
                static_cast<unsigned long long>(timestampUs), ax, ay, az, gx, gy, gz, temp);  // EN: Serialize all validated signed register counts. TH: serialize signed register count ที่อ่านครบแล้วทั้งหมด
}

void startBleTelemetry() {  // EN: Start read-only BLE telemetry. TH: เริ่ม BLE telemetry แบบอ่านอย่างเดียว
  BLEDevice::init(BLE_DEVICE_NAME);  // EN: Set the name used by the app scanner. TH: ตั้งชื่อที่แอปใช้ค้นหา
  BLEDevice::setMTU(185);  // EN: Request an MTU large enough for the compact JSON summary. TH: ขอ MTU ให้รองรับ JSON สรุปขนาดเล็ก
  BLEServer *server = BLEDevice::createServer();  // EN: Create the GATT server. TH: สร้าง GATT server
  bleServer = server;  // EN: Keep a handle for connection-aware notifications. TH: เก็บ handle ไว้ควบคุมการส่งตามสถานะการเชื่อมต่อ
  server->setCallbacks(new DozBleServerCallbacks());  // EN: Resume advertising after disconnection. TH: กลับไปประกาศตัวหลังการตัดการเชื่อมต่อ
  BLEService *service = server->createService(BLE_SERVICE_UUID);  // EN: Publish the shared Doz service. TH: ประกาศ service UUID ของ Doz
  liveCharacteristic = service->createCharacteristic(  // EN: Create the live telemetry endpoint. TH: สร้าง characteristic telemetry สด
      BLE_LIVE_UUID, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);  // EN: Allow reads and notifications. TH: อนุญาตให้อ่านและรับ notification
  liveCharacteristic->setValue("{\"type\":\"status\",\"v\":1,\"analysis_available\":false}");  // EN: Explicitly report that AI is not running here. TH: ระบุชัดว่า firmware ชุดนี้ยังไม่รัน AI
  service->start();  // EN: Activate the GATT service. TH: เริ่ม GATT service
  BLEAdvertising *advertising = BLEDevice::getAdvertising();  // EN: Configure BLE discovery. TH: ตั้งค่าการประกาศ BLE เพื่อค้นหาอุปกรณ์
  advertising->addServiceUUID(BLE_SERVICE_UUID);  // EN: Include the service UUID in advertisements. TH: ใส่ service UUID ในโฆษณา BLE
  advertising->setScanResponse(true);  // EN: Include the device name in scan response when supported. TH: ให้ scan response มีชื่ออุปกรณ์เมื่อรองรับ
  BLEDevice::startAdvertising();  // EN: Make the ESP32 discoverable. TH: เริ่มประกาศให้อุปกรณ์อื่นค้นพบ
  bleTxQueue = xQueueCreate(BLE_TX_QUEUE_LENGTH, sizeof(BlePacket));  // EN: Allocate the bounded report queue before starting its worker. TH: สร้างคิว report แบบจำกัดก่อนเริ่ม worker
  if (bleTxQueue == nullptr) {  // EN: Detect insufficient memory without stopping sensor acquisition. TH: ตรวจ RAM ไม่พอโดยไม่หยุดการเก็บ sensor
    status("ble_tx_queue_allocation_failed");  // EN: Report that live BLE sending is unavailable. TH: แจ้งว่าไม่สามารถส่ง BLE สดได้
    return;  // EN: Keep USB, sensors, and SD logging available. TH: คง USB, sensor และ SD logger ให้ทำงานต่อ
  }  // EN: Finish queue allocation validation. TH: จบการตรวจการจองคิว
  if (xTaskCreate(bleTransmitTask, "ble_tx", 4096, nullptr, 1, nullptr) != pdPASS) {  // EN: Start a low-priority worker so BLE pacing cannot block acquisition. TH: เริ่ม worker priority ต่ำเพื่อไม่ให้ pacing BLE ขวางการอ่าน sensor
    vQueueDelete(bleTxQueue);  // EN: Release the queue when no worker can consume it. TH: คืนคิวเมื่อไม่มี worker มาอ่าน
    bleTxQueue = nullptr;  // EN: Mark asynchronous BLE sending unavailable. TH: ระบุว่าการส่ง BLE แบบ asynchronous ใช้ไม่ได้
    status("ble_tx_task_start_failed");  // EN: Report the worker startup failure. TH: แจ้งเริ่ม worker ไม่สำเร็จ
    return;  // EN: Preserve all non-BLE acquisition and logging functions. TH: คงการเก็บข้อมูลและ log ที่ไม่ใช่ BLE
  }  // EN: Finish worker startup validation. TH: จบการตรวจเริ่ม worker
}

void notifyJsonFragments(const char *payload, size_t length) {  // EN: Split JSON into ATT-MTU-safe notification frames. TH: แบ่ง JSON เป็น frame ที่ปลอดภัยกับ ATT MTU
  constexpr size_t HEADER_SIZE = 6;  // EN: Reserve magic, sequence, index, and fragment-count bytes. TH: สงวน byte สำหรับ magic, sequence, index และจำนวนชิ้น
  constexpr size_t DATA_SIZE = 14;  // EN: Keep each frame within the default 20-byte ATT payload. TH: จำกัดข้อมูลให้ frame ไม่เกิน payload 20 byte มาตรฐาน
  const uint8_t total = static_cast<uint8_t>((length + DATA_SIZE - 1) / DATA_SIZE);  // EN: Calculate the number of frames. TH: คำนวณจำนวน frame ที่ต้องส่ง
  const uint16_t sequence = bleSequence++;  // EN: Assign one sequence number to this report. TH: กำหนด sequence เดียวให้ report นี้
  for (uint8_t index = 0; index < total; ++index) {  // EN: Send fragments in order. TH: ส่ง fragment ตามลำดับ
    uint8_t frame[HEADER_SIZE + DATA_SIZE];  // EN: Build one bounded notification. TH: สร้าง notification หนึ่ง frame ในขนาดจำกัด
    const size_t offset = static_cast<size_t>(index) * DATA_SIZE;  // EN: Find this fragment's payload offset. TH: หาตำแหน่งข้อมูลของ fragment นี้
    const size_t chunk = (length - offset < DATA_SIZE) ? length - offset : DATA_SIZE;  // EN: Bound the final fragment length. TH: จำกัดความยาว fragment สุดท้าย
    frame[0] = 0xD0; frame[1] = 0x5A;  // EN: Mark this as a Doz BLE fragment. TH: ระบุว่าเป็น fragment ของ Doz BLE
    frame[2] = static_cast<uint8_t>(sequence & 0xFF); frame[3] = static_cast<uint8_t>(sequence >> 8);  // EN: Store sequence little-endian. TH: เก็บ sequence แบบ little-endian
    frame[4] = index; frame[5] = total;  // EN: Store fragment index and total count. TH: เก็บ index และจำนวน fragment
    memcpy(frame + HEADER_SIZE, payload + offset, chunk);  // EN: Copy this JSON segment into the frame. TH: คัดลอกส่วน JSON ลง frame
    liveCharacteristic->setValue(frame, HEADER_SIZE + chunk);  // EN: Set the notification bytes. TH: ตั้ง byte สำหรับ notification
    liveCharacteristic->notify();  // EN: Send this frame to the subscribed app. TH: ส่ง frame ให้แอปที่ subscribe
    delay(8);  // EN: Pace notifications to reduce congestion on small-MTU phones. TH: หน่วงเพื่อลดการแออัดบนโทรศัพท์ MTU เล็ก
  }  // EN: Finish sending this report's fragments. TH: จบการส่ง fragment ของ report นี้
}

void bleTransmitTask(void *argument) {  // EN: Send queued reports away from the sensor acquisition loop. TH: ส่ง report จากคิวแยกจาก loop อ่าน sensor
  (void)argument;  // EN: This worker does not need a task argument. TH: worker นี้ไม่ต้องใช้ argument
  BlePacket packet = {};  // EN: Reserve one fixed-size report buffer for queue receives. TH: เตรียม buffer report ขนาดคงที่สำหรับอ่านจากคิว
  for (;;) {  // EN: Keep the BLE sender alive while the device runs. TH: ให้ตัวส่ง BLE ทำงานตลอดเวลาที่อุปกรณ์เปิด
    if (xQueueReceive(bleTxQueue, &packet, portMAX_DELAY) != pdTRUE) {  // EN: Sleep until a report arrives instead of polling. TH: รอจนมี report แทนการวนตรวจซ้ำ
      continue;  // EN: Retry after an unexpected queue receive failure. TH: ลองใหม่เมื่ออ่านคิวผิดพลาดโดยไม่คาดคิด
    }  // EN: Finish queue receive validation. TH: จบการตรวจรับข้อมูลจากคิว
    if (packet.length == 0 || packet.length >= BLE_JSON_CAPACITY) {  // EN: Reject empty or malformed queue items before framing. TH: ปฏิเสธ queue item ว่างหรือผิดรูปก่อนแบ่ง frame
      continue;  // EN: Drop the invalid report without touching the BLE stack. TH: ทิ้ง report ผิดโดยไม่เรียก BLE stack
    }  // EN: Finish bounded packet validation. TH: จบการตรวจขอบเขต packet
    if (liveCharacteristic == nullptr || bleServer == nullptr || bleServer->getConnectedCount() == 0) {  // EN: Drop stale reports when no phone is connected. TH: ทิ้ง report เก่าเมื่อไม่มีโทรศัพท์เชื่อมต่อ
      continue;  // EN: Do not delay acquisition trying to deliver an unavailable notification. TH: ไม่หน่วงการอ่าน sensor เพื่อส่ง notification ที่ไม่มีผู้รับ
    }  // EN: Finish connection-state validation. TH: จบการตรวจสถานะการเชื่อมต่อ
    notifyJsonFragments(packet.payload, packet.length);  // EN: Send this report with the existing MTU-safe framing protocol. TH: ส่ง report ด้วย protocol แบ่ง frame ที่รองรับ MTU เดิม
  }  // EN: Finish the background sender loop. TH: จบ loop ของตัวส่งเบื้องหลัง
}  // EN: Finish the BLE transmission worker. TH: จบ BLE transmission worker

void emitBleTelemetry(uint64_t nowUs) {  // EN: Send one-second means, without inventing AI output. TH: ส่งค่าเฉลี่ยหนึ่งวินาทีโดยไม่สร้างผล AI ขึ้นเอง
  if (liveCharacteristic == nullptr || nowUs < nextBleUs) return;  // EN: Skip before BLE is ready or before the next interval. TH: ข้ามเมื่อ BLE ไม่พร้อมหรือยังไม่ถึงรอบส่ง
  nextBleUs = nowUs + BLE_REPORT_PERIOD_US;  // EN: Schedule the next report. TH: กำหนดรอบส่งถัดไป
  const uint32_t redMean = ppgCount ? static_cast<uint32_t>(redSum / ppgCount) : 0;  // EN: Calculate mean red ADC count. TH: คำนวณ ADC แดงเฉลี่ย
  const uint32_t irMean = ppgCount ? static_cast<uint32_t>(irSum / ppgCount) : 0;  // EN: Calculate mean IR ADC count. TH: คำนวณ ADC IR เฉลี่ย
  const int32_t axMean = imuCount ? static_cast<int32_t>(axSum / imuCount) : 0;  // EN: Calculate mean X acceleration count. TH: คำนวณ acceleration X เฉลี่ย
  const int32_t ayMean = imuCount ? static_cast<int32_t>(aySum / imuCount) : 0;  // EN: Calculate mean Y acceleration count. TH: คำนวณ acceleration Y เฉลี่ย
  const int32_t azMean = imuCount ? static_cast<int32_t>(azSum / imuCount) : 0;  // EN: Calculate mean Z acceleration count. TH: คำนวณ acceleration Z เฉลี่ย
  const int32_t gxMean = imuCount ? static_cast<int32_t>(gxSum / imuCount) : 0;  // EN: Calculate mean X gyroscope count. TH: คำนวณ gyro X เฉลี่ย
  const int32_t gyMean = imuCount ? static_cast<int32_t>(gySum / imuCount) : 0;  // EN: Calculate mean Y gyroscope count. TH: คำนวณ gyro Y เฉลี่ย
  const int32_t gzMean = imuCount ? static_cast<int32_t>(gzSum / imuCount) : 0;  // EN: Calculate mean Z gyroscope count. TH: คำนวณ gyro Z เฉลี่ย
  char packet[BLE_JSON_CAPACITY];  // EN: Hold the bounded-size JSON record. TH: เตรียม buffer สำหรับ JSON ที่จำกัดขนาด
  const int written = snprintf(packet, sizeof(packet),  // EN: Serialize compact versioned telemetry fields. TH: serialize ฟิลด์ telemetry แบบกระชับพร้อม version
      "{\"type\":\"telemetry\",\"v\":1,\"t\":%llu,\"r\":%lu,\"i\":%lu,\"a\":[%ld,%ld,%ld],\"g\":[%ld,%ld,%ld],\"pn\":%lu,\"in\":%lu,\"bd\":%lu,\"ai\":false}",  // EN: Include accumulated dropped BLE reports in the compact schema. TH: ใส่ยอด BLE report ที่ข้ามไว้ใน schema แบบกระชับ
      static_cast<unsigned long long>(nowUs / 1000), static_cast<unsigned long>(redMean), static_cast<unsigned long>(irMean),  // EN: Serialize time and mean red/IR counts. TH: serialize เวลาและค่าเฉลี่ย count Red/IR
      static_cast<long>(axMean), static_cast<long>(ayMean), static_cast<long>(azMean), static_cast<long>(gxMean), static_cast<long>(gyMean), static_cast<long>(gzMean),  // EN: Serialize mean signed accel and gyro counts. TH: serialize signed count เฉลี่ยของ accel และ gyro
      static_cast<unsigned long>(ppgCount), static_cast<unsigned long>(imuCount), static_cast<unsigned long>(bleTxQueueDrops));  // EN: Finish JSON serialization with the BLE drop count. TH: จบการสร้าง JSON พร้อมยอด BLE report ที่ข้าม
  if (bleTxQueue != nullptr && bleServer != nullptr && bleServer->getConnectedCount() > 0 && written > 0 && written < static_cast<int>(sizeof(packet))) {  // EN: Queue only complete reports when BLE has a connected receiver. TH: เข้าคิวเฉพาะ report ครบและมีอุปกรณ์ BLE เชื่อมต่อ
    BlePacket queued = {};  // EN: Create a stable fixed-size snapshot for the worker. TH: สร้าง snapshot ขนาดคงที่ให้ worker
    queued.length = static_cast<uint16_t>(written);  // EN: Preserve the exact JSON length without the null terminator. TH: เก็บความยาว JSON จริงโดยไม่รวม null terminator
    memcpy(queued.payload, packet, static_cast<size_t>(written));  // EN: Copy the report before the stack buffer goes out of scope. TH: คัดลอก report ก่อน buffer บน stack หมดอายุ
    if (xQueueSendToBack(bleTxQueue, &queued, 0) == pdTRUE) {  // EN: Enqueue without blocking the sensor loop. TH: เข้าคิวโดยไม่บล็อก loop อ่าน sensor
      bleTxQueueDrops = 0;  // EN: Reset the reported drop count after a report is accepted. TH: ล้างยอด drop หลังคิวรับ report แล้ว
    } else {  // EN: Account for a report skipped due to BLE backpressure. TH: นับ report ที่ข้ามเพราะ BLE ส่งช้ากว่าข้อมูลเข้า
      ++bleTxQueueDrops;  // EN: Surface future backpressure in the next transmitted report. TH: แสดง backpressure ใน report ที่ส่งได้รอบถัดไป
    }  // EN: Finish nonblocking report enqueue handling. TH: จบการจัดการเข้าคิวแบบไม่บล็อก
  }  // EN: End payload bounds check. TH: จบการตรวจขอบเขตข้อมูล
  redSum = irSum = 0;  // EN: Reset optical sums. TH: ล้างผลรวมสัญญาณแสง
  axSum = aySum = azSum = gxSum = gySum = gzSum = 0;  // EN: Reset IMU sums. TH: ล้างผลรวม IMU
  ppgCount = imuCount = 0;  // EN: Reset interval sample counts. TH: ล้างจำนวน sample ประจำช่วง
}
}  // EN: Close the file-private namespace. TH: ปิด namespace ที่จำกัดอยู่ในไฟล์นี้

void setup() {  // EN: Initialize serial, I2C, BLE, and both sensor devices. TH: เริ่ม Serial, I2C, BLE และ sensor ทั้งสอง
  // 460800 baud leaves headroom for JSONL PPG (100 Hz) plus IMU (50 Hz) packets.
  Serial.begin(460800);  // EN: Start fast USB serial for newline-delimited PPG and IMU data. TH: เริ่ม Serial ความเร็วสูงสำหรับข้อมูล PPG และ IMU แบบ JSONL
  pinMode(SD_CD_PIN, INPUT_PULLUP);  // EN: Read the card-detect switch safely; inserted card pulls the net LOW. TH: อ่านสวิตช์ตรวจการ์ดอย่างปลอดภัย โดยการ์ดที่ใส่แล้วดึงสัญญาณลง LOW
  startSdLogger();  // EN: Mount microSD and start its independent raw-record writer. TH: mount microSD และเริ่มตัวเขียน raw แยก task
  Wire.begin();  // EN: Start I2C using the selected ESP32 board's default SDA/SCL pins. TH: เริ่ม I2C ด้วยขา SDA/SCL เริ่มต้นของบอร์ด ESP32 ที่เลือก
  Wire.setClock(400000);  // EN: Request 400 kHz I2C; verify the modules and wiring support it. TH: ตั้ง I2C 400 kHz; ต้องตรวจว่าโมดูลและสายรองรับจริง
  Wire.setTimeOut(I2C_TIMEOUT_MS);  // EN: Return control after a bounded I2C stall so the loop can report sensor errors. TH: คืนการควบคุมเมื่อ I2C ค้างตามเวลา เพื่อให้ loop แจ้ง sensor error ต่อได้
  startBleTelemetry();  // EN: Start BLE in parallel with the existing USB Serial stream. TH: เริ่ม BLE ควบคู่กับ USB Serial เดิม

  ppgReady = ppg.begin(Wire, I2C_SPEED_FAST);  // EN: Detect and initialize the MAX30102 on I2C. TH: ตรวจพบและเริ่มต้นเซนเซอร์ MAX30102 ผ่าน I2C หรือไม่
  if (ppgReady) {  // EN: Configure optical acquisition only after sensor detection succeeds. TH: ตั้งค่าการอ่านแสงเมื่อพบ sensor สำเร็จเท่านั้น
    ppg.setup(0x1F, 1, 2, 100, 411, 4096);  // EN: Configure red/IR, 100 Hz target, and one-sample averaging; verify library parameter semantics. TH: ตั้ง red/IR เป้าหมาย 100 Hz และ average=1; ตรวจความหมาย parameter ตามไลบรารีที่ติดตั้ง
    ppg.setPulseAmplitudeRed(0x24);  // EN: Set red LED drive; tune against signal quality and heating. TH: ตั้งกระแส LED แดงและปรับตามคุณภาพสัญญาณกับความร้อน
    ppg.setPulseAmplitudeIR(0x24);  // EN: Set IR LED drive; verify clipping and skin temperature in real use. TH: ตั้งกระแส LED IR และตรวจ clipping กับอุณหภูมิผิวขณะใช้งานจริง
    ppg.setPulseAmplitudeGreen(0);  // EN: Disable the unused green LED channel. TH: ปิด LED เขียวเพราะ pipeline ใช้ red/IR เท่านั้น
  } else {  // EN: Report missing optical hardware without emitting fabricated samples. TH: แจ้งว่าไม่พบ sensor แสงและไม่สร้าง sample ปลอม
    status("max30102_not_found");  // EN: Send a machine-readable MAX30102 failure status. TH: ส่งสถานะผิดพลาด MAX30102 ที่เครื่องอ่านได้
  }

  uint8_t imuIdentity = 0;  // EN: Reserve a byte for the WHO_AM_I response. TH: เตรียมตัวแปร byte สำหรับค่าตอบกลับ WHO_AM_I
  const bool imuIdentityValid = readMpuRegister(MPU6050_REG_WHO_AM_I, imuIdentity) && imuIdentity == MPU6050_ADDR;  // EN: Require the expected MPU6050 identity before configuration. TH: บังคับ identity ให้ตรง MPU6050 ก่อนตั้งค่า
  if (!imuIdentityValid) {  // EN: Keep the IMU disabled when the device identity is absent or unexpected. TH: ปิด IMU เมื่ออ่าน identity ไม่ได้หรือไม่ตรงรุ่น
    status("mpu6050_identity_error");  // EN: Report a specific identity failure to the host. TH: แจ้ง host ด้วยสถานะ identity ผิดโดยเฉพาะ
  } else {  // EN: Configure the sensor only after identity verification. TH: ตั้งค่า sensor หลังยืนยัน identity แล้วเท่านั้น
    const bool awake = writeMpuRegister(MPU6050_REG_PWR_MGMT_1, 0x00);  // EN: Wake the verified MPU6050 from sleep. TH: ปลุก MPU6050 ที่ยืนยันแล้วจาก sleep
    const bool accelRange = writeMpuRegister(MPU6050_REG_ACCEL_CONFIG, 0x00);  // EN: Select ±2 g (nominally 16384 counts/g). TH: ตั้ง ±2 g หรือ 16384 count/g
    const bool gyroRange = writeMpuRegister(MPU6050_REG_GYRO_CONFIG, 0x00);  // EN: Select ±250 degrees/s (nominally 131 counts/(degree/s)). TH: ตั้ง ±250 °/s หรือ 131 count/(°/s)
    imuReady = awake && accelRange && gyroRange;  // EN: Enable streaming only after all configuration writes succeed. TH: เริ่มสตรีมเมื่อการเขียนตั้งค่าทั้งหมดสำเร็จ
    if (!imuReady) status("mpu6050_config_error");  // EN: Report configuration failure instead of emitting readings. TH: แจ้งการตั้งค่าล้มเหลวแทนการส่งค่าที่ไม่น่าเชื่อถือ
  }  // EN: Finish identity-gated MPU6050 setup. TH: จบการตั้งค่า MPU6050 ที่ผ่าน identity gate
  status("stream_started; ppg_target_hz=100; imu_target_hz=50; verify actual rates and sensor settings");  // EN: Announce target rates while requiring measurement of actual rates. TH: แจ้งเริ่มสตรีมและระบุว่าเป็น target rate ซึ่งต้องตรวจวัดจริง
}

void loop() {  // EN: Drain PPG samples and schedule IMU/BLE work continuously. TH: อ่าน PPG และจัดตารางงาน IMU/BLE ต่อเนื่อง
  if (ppgReady) {  // EN: Poll the optical FIFO only when the sensor initialized. TH: อ่าน FIFO แสงเมื่อ sensor เริ่มสำเร็จ
    uint8_t overflowCounter = 0;  // EN: Prepare to read the sensor's five-bit dropped-sample counter. TH: เตรียมอ่านตัวนับตัวอย่างที่หายห้า bit ของ sensor
    if (!readPpgOverflowCounter(overflowCounter)) {  // EN: Require overflow status before draining FIFO data. TH: บังคับอ่านสถานะ overflow ให้ได้ก่อนดึงข้อมูล FIFO
      status("max30102_overflow_counter_read_error");  // EN: Report that sample-loss tracking is temporarily unavailable. TH: แจ้งว่าติดตามตัวอย่างที่หายไม่ได้ชั่วคราว
    } else {  // EN: Process the FIFO only after loss metadata is available. TH: ประมวลผล FIFO เมื่ออ่าน metadata การสูญหายได้แล้ว
      if (overflowCounter >= lastPpgOverflowCounter) {  // EN: Handle the counter while it has not reset after FIFO activity. TH: จัดการ counter กรณียังไม่ reset หลังอ่าน FIFO
        pendingPpgLostSamples += overflowCounter - lastPpgOverflowCounter;  // EN: Accumulate newly reported overflow events. TH: สะสมจำนวน overflow ที่รายงานเพิ่ม
      } else {  // EN: Handle the sensor counter reset after a FIFO pop. TH: จัดการกรณี counter ของ sensor reset หลังอ่าน FIFO
        pendingPpgLostSamples += overflowCounter;  // EN: Count the post-reset overflow value as new losses. TH: นับค่า overflow หลัง reset เป็นตัวอย่างที่หายรอบใหม่
      }  // EN: Finish overflow-counter delta calculation. TH: จบการคำนวณส่วนต่าง overflow counter
      lastPpgOverflowCounter = overflowCounter;  // EN: Save this counter for the next polling interval. TH: เก็บ counter นี้ไว้เทียบรอบอ่านถัดไป
      ppg.check();  // EN: Move available FIFO samples into the library's ordered buffer. TH: ดึง FIFO sample ที่มีเข้า buffer เรียงลำดับของไลบรารี
      const uint8_t queuedSamples = ppg.available();  // EN: Count buffered FIFO samples before draining. TH: นับ sample ใน buffer ก่อนอ่านออก
      if (queuedSamples > 0) {  // EN: Reconstruct time only when at least one sample is queued. TH: สร้างเวลาเมื่อมี sample ในคิวอย่างน้อยหนึ่งตัว
        const uint64_t nowUs = static_cast<uint64_t>(esp_timer_get_time());  // EN: Anchor this batch to the current monotonic clock. TH: อ้างอิง batch นี้กับนาฬิกา monotonic ปัจจุบัน
        const uint64_t backfillUs = static_cast<uint64_t>(queuedSamples - 1) * PPG_SAMPLE_PERIOD_US;  // EN: Estimate earlier sample times from nominal spacing. TH: ประมาณเวลาของ sample ก่อนหน้าจากช่วงห่าง nominal
        const uint64_t oldestEstimateUs = nowUs >= backfillUs ? nowUs - backfillUs : 0;  // EN: Estimate the oldest sample time without unsigned underflow. TH: ประมาณเวลา sample เก่าสุดโดยป้องกัน unsigned underflow
        if (!ppgTimestampInitialized) {  // EN: Initialize the sample clock on the first available FIFO batch. TH: เริ่ม sample clock เมื่อได้ FIFO batch แรก
          nextPpgTimestampUs = oldestEstimateUs;  // EN: Anchor the nominal sample clock to the first batch. TH: ตั้ง sample clock nominal จาก batch แรก
          ppgTimestampInitialized = true;  // EN: Mark the PPG clock as initialized. TH: ทำเครื่องหมายว่าเริ่ม PPG clock แล้ว
        } else {  // EN: Adjust an established clock for losses since its previous sample. TH: ปรับ clock ที่เริ่มแล้วตาม sample ที่หายหลังตัวอย่างก่อนหน้า
          const uint64_t afterKnownLossUs = nextPpgTimestampUs + static_cast<uint64_t>(pendingPpgLostSamples) * PPG_SAMPLE_PERIOD_US;  // EN: Preserve elapsed nominal periods for samples reported lost. TH: เว้นช่วง nominal ตามจำนวน sample ที่รายงานว่าหาย
          if (afterKnownLossUs > nextPpgTimestampUs) {  // EN: Advance the stream clock when loss was reported. TH: เลื่อน stream clock เมื่อมีรายงานการสูญหาย
            nextPpgTimestampUs = afterKnownLossUs;  // EN: Encode missing samples as an observable timestamp gap. TH: แสดง sample ที่หายเป็นช่องว่าง timestamp ที่ตรวจจับได้
          }  // EN: Finish loss-based timestamp adjustment. TH: จบการปรับ timestamp จาก sample ที่หาย
        }  // EN: Finish first-anchor or loss-aware clock handling. TH: จบการจัดการ clock สำหรับจุดเริ่มหรือ sample ที่หาย
        if (oldestEstimateUs > nextPpgTimestampUs) {  // EN: Correct forward if real host time shows the batch is newer. TH: เลื่อนไปข้างหน้าหากเวลาจริงบอกว่า batch ใหม่กว่า
          nextPpgTimestampUs = oldestEstimateUs;  // EN: Avoid emitting timestamps behind the measured batch estimate. TH: ป้องกันการส่ง timestamp ย้อนหลังจากค่าประมาณ batch
        }  // EN: Finish forward-only clock correction. TH: จบการปรับ clock ไปข้างหน้าเท่านั้น
        while (ppg.available()) {  // EN: Drain samples in their original FIFO order. TH: อ่าน sample ตามลำดับ FIFO เดิม
          emitPpg(nextPpgTimestampUs, pendingPpgLostSamples);  // EN: Emit the oldest FIFO reading with its estimated time and loss count. TH: ส่งค่า FIFO เก่าสุดพร้อมเวลาโดยประมาณและจำนวนที่หาย
          pendingPpgLostSamples = 0;  // EN: Attach any accumulated loss to only the first recovered sample. TH: แนบจำนวนที่หายกับ sample แรกหลังกลับมารับข้อมูลเท่านั้น
          nextPpgTimestampUs += PPG_SAMPLE_PERIOD_US;  // EN: Schedule the next sample on the configured nominal cadence. TH: กำหนดเวลาตัวอย่างถัดไปตาม cadence nominal ที่ตั้งไว้
          ppg.nextSample();  // EN: Advance the FIFO cursor after reading the current sample. TH: เลื่อน cursor FIFO หลังอ่าน sample ปัจจุบัน
        }  // EN: Finish draining all currently buffered PPG samples. TH: จบการอ่าน PPG sample ที่พักอยู่ทั้งหมด
      }  // EN: Finish handling a non-empty FIFO batch. TH: จบการจัดการ FIFO batch ที่มีข้อมูล
    }
  }
  const uint64_t nowUs = static_cast<uint64_t>(esp_timer_get_time());  // EN: Read monotonic time for IMU and BLE scheduling. TH: อ่านเวลาปัจจุบันเพื่อกำหนดรอบ IMU และ BLE
  if (imuReady && nowUs >= nextImuUs) {  // EN: Read IMU only when ready and its schedule is due. TH: อ่าน IMU เมื่อพร้อมและถึงกำหนดเวลา
    emitImu();  // EN: Read and emit accelerometer, gyroscope, and die temperature. TH: อ่านและส่ง accelerometer, gyroscope และ die temperature
    nextImuUs = nowUs + IMU_PERIOD_US;  // EN: Schedule the next read; serial work can change the measured rate. TH: ตั้งเวลาอ่านรอบถัดไป; ภาระ Serial อาจทำให้ rate จริงคลาดเคลื่อน
  }
  emitBleTelemetry(nowUs);  // EN: Send a compact one-second summary to the app. TH: ส่งสรุปขนาดเล็กทุกวินาทีไปยังแอป
  if (!sdReady && !sdFailureReported) {  // EN: Report a runtime SD writer failure once without spamming JSONL. TH: รายงาน SD ล้มเหลวระหว่างทำงานครั้งเดียว ไม่ให้รบกวน JSONL ซ้ำ
    status("sd_logging_unavailable; check_card_and_sequence_gaps");  // EN: Tell the host that later sequence gaps may reflect storage failure. TH: แจ้ง host ว่า sequence gap หลังจากนี้อาจเกิดจาก storage failure
    sdFailureReported = true;  // EN: Suppress duplicate failure messages. TH: ปิดการส่งข้อความ failure ซ้ำ
  }  // EN: Finish one-time SD failure reporting. TH: จบการรายงาน SD failure ครั้งเดียว
  delay(1);  // EN: Yield briefly so the loop does not spin continuously at full CPU usage. TH: เว้นรอบสั้น ๆ เพื่อไม่ให้ loop หมุนกิน CPU ทั้งหมด
}
