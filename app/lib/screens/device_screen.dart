import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../ui_text.dart';

// EN: Connect to BLE and distinguish transport, packet arrival, and AI availability.
// TH: เชื่อม BLE และแยกสถานะการเชื่อม การรับ packet และผล AI ออกจากกัน
class DeviceScreen extends StatelessWidget {
  const DeviceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DozState>();
    String copy(String en, String th) => uiText(context, english: en, thai: th);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(copy('My device', 'อุปกรณ์ของฉัน'),
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(copy('Connect to Doz over Bluetooth Low Energy (BLE).',
            'เชื่อมต่อ Doz ผ่าน Bluetooth Low Energy (BLE)')),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF11141B),
            border: Border.all(color: const Color(0xFF232833)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Icon(state.bleConnected ? Icons.watch : Icons.watch_outlined,
                  size: 34,
                  color: state.bleConnected
                      ? const Color(0xFF55D6A7)
                      : const Color(0xFFA7B0C0)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        state.bleConnected
                            ? state.bleDeviceName
                            : copy('Not connected', 'ยังไม่เชื่อมต่อ'),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                        state.bleConnected
                            ? localizedBleStatus(context, state.bleStatus)
                            : '${copy('Status', 'สถานะ')}: ${localizedBleStatus(context, state.bleStatus)}',
                        style: const TextStyle(
                            color: Color(0xFF8B93A3), fontSize: 12)),
                  ],
                ),
              ),
              if (state.bleConnected)
                IconButton(
                  tooltip: copy('Disconnect', 'ยกเลิกการเชื่อมต่อ'),
                  onPressed: state.disconnectBle,
                  icon: const Icon(Icons.link_off),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: state.scanningBle ? null : state.scanForDevices,
          icon: state.scanningBle
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.bluetooth_searching),
          label: Text(state.scanningBle
              ? copy('Searching…', 'กำลังค้นหา…')
              : copy('Find nearby devices', 'ค้นหาอุปกรณ์ใกล้เคียง')),
        ),
        if (_needsPermissionSettings(state.bleStatus)) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: openAppSettings,
            icon: const Icon(Icons.settings_outlined),
            label: Text(copy('Open app settings', 'เปิดการตั้งค่าแอป')),
          ),
        ],
        if (_needsLocationSettings(state.bleStatus)) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: Geolocator.openLocationSettings,
            icon: const Icon(Icons.location_on_outlined),
            label:
                Text(copy('Open Location settings', 'เปิดการตั้งค่าตำแหน่ง')),
          ),
        ],
        const SizedBox(height: 10),
        _HintCard(
          icon: Icons.tips_and_updates_outlined,
          text: copy(
            'Keep the powered-on board nearby. Allow Nearby devices on Android or Bluetooth on iPhone when asked. BLE devices do not need to be paired in system Settings; connect from this screen.',
            'เปิดบอร์ดและวางไว้ใกล้โทรศัพท์ อนุญาตสิทธิ์อุปกรณ์ใกล้เคียงบน Android หรือ Bluetooth บน iPhone เมื่อระบบถาม ไม่ต้องจับคู่ใน Settings ให้เชื่อมต่อจากหน้านี้',
          ),
        ),
        if (state.scanningBle)
          TextButton.icon(
            onPressed: state.cancelBleScan,
            icon: const Icon(Icons.close),
            label: Text(copy('Cancel search', 'ยกเลิกการค้นหา')),
          ),
        if (state.scannedBleDevices.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
              '${copy('Found devices', 'อุปกรณ์ที่พบ')} (${state.scannedBleDevices.length})',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...state.scannedBleDevices.map(
            (result) => _DeviceTile(
              result: result,
              busy: state.scanningBle,
              connected: state.bleConnected &&
                  state.bleDeviceId == result.device.remoteId.str,
            ),
          ),
        ] else ...[
          const SizedBox(height: 16),
          _HintCard(
            icon: Icons.info_outline,
            text: copy(
              'Turn on the prototype and allow Bluetooth when prompted, then scan. The prototype must be advertising over BLE.',
              'เปิดอุปกรณ์ต้นแบบและอนุญาต Bluetooth เมื่อระบบถาม จากนั้นกดค้นหา โดยอุปกรณ์ต้องกำลังประกาศ BLE อยู่',
            ),
          ),
        ],
        const SizedBox(height: 16),
        _LiveTelemetryCard(state: state),
        const SizedBox(height: 12),
        _HintCard(
          icon: Icons.sensors_outlined,
          text: copy(
            'Current firmware streams one-second mean raw Red/IR and MPU6050 values. It does not send AI results, heart rate, SpO₂, or battery percentage yet.',
            'เฟิร์มแวร์ปัจจุบันส่งค่าเฉลี่ยดิบ Red/IR และ MPU6050 ทุก 1 วินาที ยังไม่ส่งผล AI, อัตราการเต้นหัวใจ, SpO₂ หรือเปอร์เซ็นต์แบตเตอรี่',
          ),
        ),
        const SizedBox(height: 12),
        _HintCard(
          icon: Icons.science_outlined,
          text: copy(
            'Without a real device, demo values may be shown. Demo data is not measured by a sensor.',
            'หากยังไม่มีอุปกรณ์จริง แอปอาจแสดงข้อมูลสาธิต ซึ่งไม่ได้วัดจากเซนเซอร์',
          ),
        ),
      ],
    );
  }

  bool _needsPermissionSettings(String status) {
    final normalized = status.toLowerCase();
    return normalized.contains('denied') ||
        normalized.contains('blocked') ||
        normalized.contains('permission');
  }

  bool _needsLocationSettings(String status) =>
      status.toLowerCase().contains('location services');
}

// EN: Display received optical and motion telemetry without treating it as inference.
// TH: แสดงค่าแสงและการเคลื่อนไหวที่รับได้โดยไม่เรียกว่าเป็นผลทำนาย
class _LiveTelemetryCard extends StatelessWidget {
  const _LiveTelemetryCard({required this.state});

  final DozState state;

  @override
  Widget build(BuildContext context) {
    final raw = state.currentSensor;
    // EN: A connected link and non-null ADC fields do not prove device origin.
    // TH: เชื่อมต่อแล้วและมีค่า ADC ไม่เพียงพอที่จะยืนยันว่ามาจากอุปกรณ์
    final hasRaw = raw.rawRed != null && raw.rawIr != null;
    final hasDevicePacket =
        state.bleConnected && state.lastReadingWasFromDevice && hasRaw;
    // EN: Use full duration precision to reject future and stale receive times.
    // TH: ใช้เวลาแบบละเอียดเพื่อปฏิเสธเวลาที่อยู่อนาคตหรือเก่าเกิน
    final observedAt = state.lastSensorUpdateAt;
    final age =
        observedAt == null ? null : DateTime.now().difference(observedAt);
    final fresh = hasDevicePacket &&
        age != null &&
        !age.isNegative &&
        age <= const Duration(seconds: 8);
    String copy(String en, String th) => uiText(context, english: en, thai: th);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF11141B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF232833)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sensors_outlined,
                  color: Color(0xFF55D6A7), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(copy('Live sensor check', 'ตรวจข้อมูลเซนเซอร์สด'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        )),
              ),
              _LiveDot(
                active: fresh,
                semanticLabel: fresh
                    ? copy('Fresh sensor data', 'ข้อมูลเซนเซอร์เป็นปัจจุบัน')
                    : copy('No fresh sensor data', 'ไม่มีข้อมูลเซนเซอร์ล่าสุด'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            !state.bleConnected
                ? copy('Connect a device to verify incoming data.',
                    'เชื่อมต่ออุปกรณ์เพื่อทดสอบการรับข้อมูล')
                : !hasDevicePacket
                    ? copy('Connected — waiting for the first sensor packet.',
                        'เชื่อมต่อแล้ว — กำลังรอข้อมูลเซนเซอร์ชุดแรก')
                    : fresh
                        ? copy('Receiving live raw telemetry',
                            'กำลังรับข้อมูลดิบจากอุปกรณ์')
                        : age == null || age.isNegative
                            ? copy(
                                'Packet time unavailable; freshness cannot be verified.',
                                'ตรวจสอบเวลาของข้อมูลไม่ได้ จึงยืนยันความใหม่ของข้อมูลไม่ได้',
                              )
                            : copy(
                                'No recent packet • last update ${age.inSeconds} s ago',
                                'ไม่ได้รับข้อมูลล่าสุด • อัปเดตล่าสุด ${age.inSeconds} วินาทีก่อน',
                              ),
            style: const TextStyle(color: Color(0xFFA7B0C0), fontSize: 13),
          ),
          // EN: Keep the last received values visible, but label stale data above.
          // TH: คงค่าที่เคยรับไว้ แต่ระบุข้างบนเมื่อข้อมูลเก่า
          if (hasDevicePacket) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF3A2B17),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                copy(
                  'Prototype telemetry only. BLE sender identity is not cryptographically verified; do not use it for safety decisions.',
                  'ข้อมูล telemetry สำหรับต้นแบบเท่านั้น ระบบยังไม่ยืนยันตัวตนผู้ส่ง BLE ด้วยการเข้ารหัส ห้ามใช้ตัดสินใจด้านความปลอดภัย',
                ),
                style: const TextStyle(
                  color: Color(0xFFFFD79B),
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _ReadingChip(label: 'Red (ADC)', value: '${raw.rawRed}'),
                _ReadingChip(label: 'IR (ADC)', value: '${raw.rawIr}'),
                _ReadingChip(
                    label: 'Accel X',
                    value: '${raw.accelX.toStringAsFixed(2)} m/s²'),
                _ReadingChip(
                    label: 'Accel Y',
                    value: '${raw.accelY.toStringAsFixed(2)} m/s²'),
                _ReadingChip(
                    label: 'Accel Z',
                    value: '${raw.accelZ.toStringAsFixed(2)} m/s²'),
                _ReadingChip(
                    label: 'Gyro X',
                    value: '${raw.gyroX.toStringAsFixed(2)} °/s'),
                _ReadingChip(
                    label: 'Gyro Y',
                    value: '${raw.gyroY.toStringAsFixed(2)} °/s'),
                _ReadingChip(
                    label: 'Gyro Z',
                    value: '${raw.gyroZ.toStringAsFixed(2)} °/s'),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(
            copy(
              'This confirms BLE data arrival only. The current firmware does not send an AI prediction.',
              'ส่วนนี้ยืนยันเพียงว่า BLE รับข้อมูลได้ เฟิร์มแวร์ปัจจุบันยังไม่ส่งผลทำนายจาก AI',
            ),
            style: const TextStyle(color: Color(0xFF8B93A3), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// EN: Pair one physical measurement with its unit.
// TH: แสดงค่าที่วัดจริงหนึ่งรายการพร้อมหน่วย
class _ReadingChip extends StatelessWidget {
  const _ReadingChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0B0D12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF343B4A)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: Color(0xFF8B93A3), fontSize: 11)),
            const SizedBox(height: 3),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

// EN: Expose packet freshness to both sighted and screen-reader users.
// TH: แสดงความใหม่ของ packet ทั้งแบบจุดสีและคำอ่านหน้าจอ
class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.active, required this.semanticLabel});

  final bool active;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
        label: semanticLabel,
        liveRegion: true,
        child: ExcludeSemantics(
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: active ? const Color(0xFF55D6A7) : const Color(0xFFFFC56A),
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
}

// EN: List one discovered BLE advertiser and start connection on tap.
// TH: แสดงอุปกรณ์ BLE ที่พบหนึ่งรายการและเริ่มเชื่อมเมื่อกด
class _DeviceTile extends StatelessWidget {
  const _DeviceTile(
      {required this.result, required this.busy, required this.connected});

  final ScanResult result;
  final bool busy;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final name = result.device.platformName.trim().isEmpty
        ? result.advertisementData.advName.trim()
        : result.device.platformName;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.bluetooth),
        title: Text(name.isEmpty
            ? uiText(context, english: 'BLE device', thai: 'อุปกรณ์ BLE')
            : name),
        subtitle:
            Text('${result.device.remoteId.str}\nRSSI ${result.rssi} dBm'),
        isThreeLine: true,
        trailing: connected
            ? const Icon(Icons.check_circle, color: Color(0xFF55D6A7))
            : const Icon(Icons.chevron_right),
        onTap: busy || connected
            ? null
            : () async {
                final ok =
                    await context.read<DozState>().connectScannedDevice(result);
                if (!context.mounted) return;
                final message = ok
                    ? uiText(context,
                        english: 'Device connected',
                        thai: 'เชื่อมต่ออุปกรณ์แล้ว')
                    : uiText(context,
                        english:
                            'Could not connect. Check firmware compatibility and try again.',
                        thai:
                            'เชื่อมต่อไม่สำเร็จ ตรวจสอบความเข้ากันได้ของเฟิร์มแวร์แล้วลองอีกครั้ง');
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(message)));
              },
      ),
    );
  }
}

// EN: Present setup or firmware limitations alongside controls.
// TH: แสดงคำแนะนำการตั้งค่าหรือข้อจำกัดเฟิร์มแวร์ข้างปุ่มควบคุม
class _HintCard extends StatelessWidget {
  const _HintCard({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF11141B),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF232833)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: const Color(0xFF8B93A3)),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(height: 1.35))),
          ],
        ),
      );
}
