#!/usr/bin/env python3
"""EN: Check the Flutter/ESP32 BLE wire contract. TH: ตรวจสัญญาข้อมูล BLE ระหว่าง Flutter กับ ESP32"""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]  # EN: Resolve from this script, not the caller's cwd. TH: หา root จากตำแหน่งสคริปต์ ไม่อิงโฟลเดอร์ที่เรียก
APP_BLE = ROOT / "app/lib/services/ble_service.dart"  # EN: Read the app decoder and UUIDs. TH: อ่าน decoder กับ UUID ฝั่งแอป
APP_FRAMES = ROOT / "app/lib/services/ble_frame_assembler.dart"  # EN: Read fragment framing rules. TH: อ่านกฎประกอบ fragment
FIRMWARE = ROOT / "model/drowines/device/firmware/max30102_mpu6050_pipeline/arduino/max30102_mpu6050_stream_esp32/max30102_mpu6050_stream_esp32.ino"  # EN: Read the current acquisition firmware. TH: อ่าน firmware เก็บข้อมูลรุ่นปัจจุบัน


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"BLE contract check failed: {message}")


def dart_string(source: str, name: str) -> str:
    match = re.search(rf"{re.escape(name)}\s*=\s*'([^']+)'", source)
    require(match is not None, f"missing Dart constant {name}")
    return match.group(1).lower()


def cpp_string(source: str, name: str) -> str:
    match = re.search(rf'{re.escape(name)}\[\]\s*=\s*"([^"]+)"', source)
    require(match is not None, f"missing firmware constant {name}")
    return match.group(1).lower()


def main() -> None:
    # EN: Missing source is a clear contract failure, not a Python traceback. TH: ถ้า source หายให้แจ้งความผิดสัญญาแทน traceback
    require(APP_BLE.is_file() and APP_FRAMES.is_file() and FIRMWARE.is_file(), "app BLE source or acquisition firmware is missing")
    app_ble = APP_BLE.read_text(encoding="utf-8")
    app_frames = APP_FRAMES.read_text(encoding="utf-8")
    firmware = FIRMWARE.read_text(encoding="utf-8")

    service_uuid = dart_string(app_ble, "defaultServiceUuid")
    live_uuid = dart_string(app_ble, "defaultLiveCharacteristicUuid")
    require(service_uuid == cpp_string(firmware, "BLE_SERVICE_UUID"), "service UUID differs")
    require(live_uuid == cpp_string(firmware, "BLE_LIVE_UUID"), "live characteristic UUID differs")

    device_name = cpp_string(firmware, "BLE_DEVICE_NAME")
    require("contains('doz')" in app_ble.lower(), "app scanner no longer accepts Doz advertisements")
    require("doz" in device_name, "firmware advertising name does not include Doz")

    wire_fields = (r'\"type\":\"telemetry\"', r'\"v\":1', r'\"t\":',
                   r'\"r\":', r'\"i\":', r'\"a\":[', r'\"g\":[',
                   r'\"pn\":', r'\"in\":', r'\"ai\":false')
    packet_template = next(
        (line for line in firmware.splitlines()
         if r'\"type\":\"telemetry\"' in line),
        None,
    )
    require(packet_template is not None, "firmware telemetry JSON template is missing")
    for field in wire_fields:
        require(field in packet_template, f"firmware telemetry field missing: {field}")
    for field in ("'type'", "'v'", "'t'", "'r'", "'i'", "'a'", "'g'", "'pn'", "'in'", "'ai'"):
        require(field in app_ble, f"app decoder no longer handles {field}")

    require("frame[0] = 0xD0" in firmware and "frame[1] = 0x5A" in firmware,
            "firmware frame magic changed")
    require("bytes[0] != 0xD0 || bytes[1] != 0x5A" in app_frames,
            "app frame magic changed")

    print("BLE app/firmware contract OK: UUIDs, Doz discovery, v1 telemetry fields, and frame magic match.")


if __name__ == "__main__":
    main()
