/// EN: Reassembles Doz notifications split for BLE's limited ATT payload. TH: ประกอบ notification ของ Doz ที่แบ่งตามขนาด ATT ของ BLE
class DozBleFrameAssembler {
  // EN: Define the stateful BLE fragment reassembler. TH: ประกาศตัวประกอบ fragment BLE ที่เก็บสถานะระหว่างรับข้อมูล
  // EN: Hold bounded fragment state for one packet. TH: เก็บ fragment ของ packet เดียวโดยจำกัดขนาด
  static const int
      _maxFragmentPayloadBytes = // EN: Set the maximum payload bytes permitted in each fragment. TH: กำหนดจำนวน byte payload สูงสุดต่อ fragment
      14; // EN: Match the firmware fragment payload limit. TH: ให้ตรงกับเพดาน payload ต่อ fragment ของ firmware
  static const int
      _maxPacketBytes = // EN: Set the maximum assembled payload size. TH: กำหนดขนาด payload สูงสุดหลังประกอบ
      191; // EN: Reserve the 192nd firmware buffer byte for NUL. TH: สงวน byte ที่ 192 ของ firmware buffer ไว้ปิดข้อความด้วย NUL
  static const Duration _partialPacketTimeout = Duration(
      // EN: Configure expiry duration for incomplete packets. TH: กำหนดเวลาหมดอายุของ packet ที่ประกอบไม่ครบ
      seconds: // EN: Express the timeout in seconds. TH: ระบุหน่วย timeout เป็นวินาที
          2); // EN: Expire incomplete frames promptly. TH: หมดอายุ frame ที่ประกอบไม่ครบอย่างรวดเร็ว

  int? // EN: Store the active packet sequence, or null when idle. TH: เก็บ sequence ของ packet ปัจจุบัน หรือ null เมื่อไม่มี packet ค้าง
      _sequence; // EN: Track the currently assembled packet ID. TH: ติดตาม ID ของ packet ที่กำลังประกอบ
  int _total = // EN: Initialize the expected fragment count. TH: ตั้งจำนวน fragment ที่คาดว่าจะได้รับ
      0; // EN: Store the expected number of fragments. TH: เก็บจำนวน fragment ที่คาดว่าจะได้รับ
  int _bufferedBytes = // EN: Initialize the buffered payload byte counter. TH: ตั้งตัวนับ byte payload ที่พักไว้
      0; // EN: Account for payload bytes held in memory. TH: นับ byte payload ที่พักในหน่วยความจำ
  final Map<int, List<int>>
      _parts = // EN: Create the fragment-index-to-payload map. TH: สร้าง map จาก index fragment ไปยัง payload
      {}; // EN: Store each payload by its zero-based fragment index. TH: เก็บ payload ตาม index fragment ที่เริ่มจากศูนย์
  Stopwatch? // EN: Hold the timer for the active incomplete packet. TH: เก็บตัวจับเวลาของ packet ที่ยังประกอบไม่ครบ
      _packetAge; // EN: Measure how long the current partial frame has been retained. TH: วัดเวลาที่เก็บ frame ซึ่งยังประกอบไม่ครบ

  List<int>? add(List<int> bytes) {
    // EN: Process one BLE notification and return a packet only when complete. TH: ประมวลผล BLE notification หนึ่งชุดและคืน packet เมื่อครบเท่านั้น
    // EN: Add one notification and return complete Doz bytes when ready. TH: รับ notification หนึ่งชุดและคืน byte Doz เมื่อประกอบครบ
    final packetAge = // EN: Read the current packet timer before checking expiry. TH: อ่าน timer ของ packet ปัจจุบันก่อนตรวจหมดอายุ
        _packetAge; // EN: Snapshot the active timer safely. TH: อ่านตัวจับเวลาปัจจุบันอย่างปลอดภัย
    if (packetAge != null && packetAge.elapsed > _partialPacketTimeout) {
      // EN: Check whether the incomplete packet exceeded its retention time. TH: ตรวจว่า packet ที่ค้างเกินเวลาที่กำหนดหรือยัง
      // EN: Drop stale fragments before considering the new notification. TH: ทิ้ง fragment เก่าก่อนพิจารณา notification ใหม่
      reset(); // EN: Release stale state and its timer. TH: ล้างสถานะเก่าและตัวจับเวลา
    } // EN: Finish partial-frame expiry handling. TH: จบการจัดการ frame ที่หมดอายุ
    if (bytes.length >
            _maxPacketBytes || // EN: Reject a notification exceeding the absolute byte limit. TH: ปฏิเสธ notification ที่เกินขีดจำกัด byte
        bytes.any((byte) => byte < 0 || byte > 255)) {
      // EN: Also reject integer values outside the unsigned-byte range. TH: ปฏิเสธค่าจำนวนเต็มที่อยู่นอกช่วง unsigned byte ด้วย
      // EN: Bound every packet and validate wire-byte values before inspecting headers. TH: จำกัดทุก packet และตรวจค่า byte ก่อนอ่าน header
      reset(); // EN: Clear partial state after invalid input. TH: ล้าง frame ค้างเมื่อ input ไม่ถูกต้อง
      return null; // EN: Reject oversized or non-byte input. TH: ปฏิเสธข้อมูลใหญ่เกินหรือไม่ใช่ byte
    } // EN: Finish universal input validation. TH: จบการตรวจ input ทุกชนิด
    if (bytes.length < 2 || bytes[0] != 0xD0 || bytes[1] != 0x5A) {
      // EN: Detect whether this notification begins with the Doz frame signature. TH: ตรวจว่า notification เริ่มด้วย signature ของ Doz หรือไม่
      // EN: Preserve non-Doz packets for the legacy decoder. TH: ส่ง packet ที่ไม่มี magic ของ Doz ต่อให้ตัวถอดรหัสเดิม
      reset(); // EN: Prevent an unrelated packet from leaving stale fragments active. TH: ป้องกัน packet อื่นทิ้ง fragment เก่าค้างไว้
      return bytes; // EN: Pass through unframed notification bytes unchanged. TH: ส่ง notification ที่ไม่ใช่ frame ต่อโดยไม่แก้ข้อมูล
    } // EN: Finish the non-Doz pass-through branch. TH: จบทางผ่านสำหรับ packet ที่ไม่ใช่ Doz

    if (bytes.length < 6 || bytes.length > 6 + _maxFragmentPayloadBytes) {
      // EN: Require a full six-byte header and a bounded fragment payload. TH: บังคับ header ครบหก byte และ payload fragment อยู่ในขอบเขต
      // EN: Enforce the complete header and maximum frame size before scanning/copying. TH: บังคับ header ครบและขนาดสูงสุดก่อนวนตรวจหรือคัดลอก
      reset(); // EN: Drop any partial packet before rejecting malformed input. TH: ล้าง packet ที่ค้างก่อนปฏิเสธ input ผิดรูป
      return null; // EN: Reject truncated or oversized frames without scanning their contents. TH: ปฏิเสธ frame ที่ถูกตัดหรือใหญ่เกินโดยไม่วนตรวจเนื้อหาทั้งชุด
    } // EN: Finish bounded frame-length validation. TH: จบการตรวจความยาว frame ภายใต้เพดาน

    if (bytes.length == 6) {
      // EN: Detect a frame containing a header but no payload. TH: ตรวจ frame ที่มี header แต่ไม่มี payload
      // EN: A fragment must carry at least one payload byte. TH: fragment ต้องมี payload อย่างน้อยหนึ่ง byte
      reset(); // EN: Clear any earlier packet fragments. TH: ล้าง fragment ก่อนหน้าที่พักไว้
      return null; // EN: Reject a header-only frame. TH: ปฏิเสธ frame ที่มีแต่ header
    } // EN: Finish empty-payload rejection. TH: จบการปฏิเสธ payload ว่าง

    final sequence = bytes[
            // EN: Begin decoding the two-byte sequence number. TH: เริ่มถอดรหัส sequence number ขนาดสอง byte
            2] | // EN: Use the low byte as the least-significant part of the ID. TH: ใช้ byte ต่ำเป็นส่วนบิตนัยสำคัญต่ำของ ID
        (bytes[3] << // EN: Shift the high byte into the upper eight bits. TH: เลื่อน byte สูงไปยังแปดบิตบน
            8); // EN: Combine both bytes into one little-endian packet ID. TH: รวมสอง byte เป็น packet ID แบบ little-endian
    final index = bytes[
        // EN: Begin reading the fragment's position in the packet. TH: เริ่มอ่านตำแหน่งของ fragment ใน packet
        4]; // EN: Read this fragment's zero-based index. TH: อ่าน index ของ fragment นี้ที่เริ่มจากศูนย์
    final total = bytes[
        // EN: Begin reading how many fragments form this packet. TH: เริ่มอ่านจำนวน fragment ที่ประกอบเป็น packet นี้
        5]; // EN: Read the total number of fragments in the packet. TH: อ่านจำนวน fragment ทั้งหมดใน packet
    if (total == 0 || total > 14 || index >= total) {
      // EN: Reject impossible fragment counts and out-of-range indexes. TH: ปฏิเสธจำนวน fragment ที่เป็นไปไม่ได้และ index ที่เกินช่วง
      // EN: Enforce valid count/index and the firmware buffer-derived maximum. TH: ตรวจ count/index และเพดานที่คำนวณจาก buffer firmware
      reset(); // EN: Discard any earlier fragments for this packet. TH: ทิ้ง fragment ก่อนหน้าของ packet นี้
      return null; // EN: Reject malformed fragment metadata. TH: ปฏิเสธ metadata ของ fragment ที่ผิด
    } // EN: Finish fragment metadata validation. TH: จบการตรวจ metadata fragment

    if (_sequence != sequence) {
      // EN: Determine whether this fragment belongs to a different packet. TH: ตรวจว่า fragment นี้เป็นของ packet คนละชุดหรือไม่
      // EN: Detect a new packet or an interleaved fragment stream. TH: ตรวจ packet ใหม่หรือ stream fragment ที่สลับกัน
      reset(); // EN: Drop fragments belonging to the previous packet. TH: ทิ้ง fragment ที่เป็นของ packet ก่อนหน้า
      _sequence = // EN: Store the new packet sequence identifier. TH: บันทึก sequence identifier ของ packet ใหม่
          sequence; // EN: Start tracking the new packet ID. TH: เริ่มติดตาม ID packet ใหม่
      _total = // EN: Store the fragment count announced by this packet. TH: บันทึกจำนวน fragment ที่ packet นี้ประกาศ
          total; // EN: Lock the expected fragment count for this packet. TH: ล็อกจำนวน fragment ที่คาดไว้ของ packet นี้
      _packetAge =
          Stopwatch() // EN: Create a timer for the newly started packet. TH: สร้าง timer สำหรับ packet ที่เพิ่งเริ่มประกอบ
            ..start(); // EN: Start expiry timing for the new partial packet. TH: เริ่มจับเวลาหมดอายุของ packet ที่เริ่มประกอบ
    } // EN: Finish new-packet initialization. TH: จบการเริ่ม packet ใหม่
    if (total != _total) {
      // EN: Ensure later fragments agree with the packet's original fragment count. TH: ตรวจ fragment ถัดไปให้ใช้จำนวนรวมตรงกับ fragment แรก
      // EN: Reject a packet whose fragment count changes midstream. TH: ปฏิเสธ packet ที่จำนวน fragment เปลี่ยนระหว่างรับ
      reset(); // EN: Clear inconsistent fragments. TH: ล้าง fragment ที่ไม่สอดคล้องกัน
      return null; // EN: Do not assemble a packet with conflicting metadata. TH: ไม่ประกอบ packet ที่ metadata ขัดแย้งกัน
    } // EN: Finish fragment-count consistency check. TH: จบการตรวจจำนวน fragment ให้คงที่

    final previousPartLength = _parts[index]
            ?.length ?? // EN: Read the stored size if this fragment index is being retransmitted. TH: อ่านขนาดเดิมถ้า fragment index นี้ถูกส่งซ้ำ
        0; // EN: Account for retransmission without double-counting memory. TH: รองรับการส่งซ้ำโดยไม่บวกหน่วยความจำซ้ำ
    final nextBufferedBytes = // EN: Calculate memory use after replacing or adding this fragment. TH: คำนวณหน่วยความจำหลังแทนที่หรือเพิ่ม fragment นี้
        _bufferedBytes - // EN: Remove the old payload size for this fragment index. TH: หักขนาด payload เก่าของ fragment index นี้
            previousPartLength + // EN: Add the replacement fragment's payload size next. TH: เตรียมบวกขนาด payload ของ fragment ทดแทน
            (bytes.length - // EN: Exclude the fixed header from the incoming size. TH: ตัดขนาด header คงที่ออกจากข้อมูลขาเข้า
                6); // EN: Compute the new total buffered payload bytes. TH: คำนวณจำนวน byte payload ที่พักใหม่ทั้งหมด
    if (nextBufferedBytes > _maxPacketBytes) {
      // EN: Verify the complete payload remains within the packet limit. TH: ตรวจ payload รวมไม่ให้เกินขนาด packet
      // EN: Reject a reconstruction larger than the firmware packet buffer. TH: ปฏิเสธข้อมูลรวมที่ใหญ่กว่า packet buffer ของ firmware
      reset(); // EN: Release all fragments after the size violation. TH: ล้าง fragment ทั้งหมดหลังละเมิดขนาด
      return null; // EN: Stop before allocating an oversized packet. TH: หยุดก่อนสร้าง packet ที่ใหญ่เกิน
    } // EN: Finish assembled-size enforcement. TH: จบการบังคับขนาดข้อมูลรวม
    _parts[index] = bytes.sublist(
        // EN: Store only the payload portion of this fragment. TH: เก็บเฉพาะส่วน payload ของ fragment นี้
        6); // EN: Copy only the payload, excluding the six-byte header. TH: คัดลอกเฉพาะ payload โดยตัด header หก byte ออก
    _bufferedBytes = // EN: Update the byte counter after accepting this fragment. TH: อัปเดตตัวนับ byte หลังรับ fragment นี้
        nextBufferedBytes; // EN: Record the current bounded memory use. TH: บันทึกหน่วยความจำที่ใช้ซึ่งถูกจำกัดแล้ว
    if (_parts.length != _total) {
      // EN: Check whether all expected fragment indexes have arrived. TH: ตรวจว่าได้รับ fragment ครบตามจำนวนที่คาดหรือยัง
      // EN: Wait until all expected indexes have arrived. TH: รอจนได้รับ index ครบตามจำนวนที่คาดไว้
      return null; // EN: Signal that the Doz packet is still incomplete. TH: แจ้งว่า packet Doz ยังประกอบไม่ครบ
    } // EN: Finish incomplete-packet handling. TH: จบการจัดการ packet ที่ยังไม่ครบ

    final packet = // EN: Prepare the final ordered payload buffer. TH: เตรียม buffer สำหรับ payload สุดท้ายตามลำดับ
        <int>[]; // EN: Allocate the bounded output packet. TH: สร้าง packet ผลลัพธ์ภายใต้เพดานขนาด
    for (var part = 0; part < _total; part++) {
      // EN: Iterate through fragment indexes from first to last. TH: วนผ่าน index fragment จากตัวแรกไปตัวสุดท้าย
      // EN: Visit fragment indexes in their original wire order. TH: วน index fragment ตามลำดับบนสายสัญญาณ
      final payload = _parts[
          // EN: Look up the payload expected at the current index. TH: ค้น payload ที่ควรอยู่ใน index ปัจจุบัน
          part]; // EN: Fetch the payload for the next expected index. TH: ดึง payload ของ index ถัดไปตามลำดับ
      if (payload == null) {
        // EN: Detect any missing fragment before returning data. TH: ตรวจ fragment ที่หายก่อนคืนข้อมูล
        // EN: Defend against an unexpected gap in the fragment map. TH: ป้องกันกรณี map ไม่มี fragment ที่ควรมี
        reset(); // EN: Clear the inconsistent packet state. TH: ล้างสถานะ packet ที่ไม่สอดคล้อง
        return null; // EN: Reject rather than return partial or reordered data. TH: ปฏิเสธแทนการคืนข้อมูลไม่ครบหรือลำดับผิด
      } // EN: Finish missing-fragment handling. TH: จบการจัดการ fragment ที่หาย
      packet.addAll(
          // EN: Append the fragment payload to the final buffer. TH: เพิ่ม payload fragment ต่อท้าย buffer สุดท้าย
          payload); // EN: Append this fragment's bytes in order. TH: ต่อ byte ของ fragment นี้ตามลำดับ
    } // EN: Finish ordered packet reconstruction. TH: จบการประกอบ packet ตามลำดับ
    reset(); // EN: Release retained fragments before returning the completed packet. TH: ล้าง fragment ที่พักไว้ก่อนคืน packet ที่ครบ
    return packet; // EN: Deliver the full payload to the telemetry decoder. TH: ส่ง payload ทั้งชุดให้ตัวถอดรหัส telemetry
  } // EN: Finish processing one notification. TH: จบการประมวลผล notification หนึ่งชุด

  void reset() {
    // EN: Reset packet metadata, timer, and all buffered fragment data. TH: ล้าง metadata, timer และข้อมูล fragment ที่พักไว้ทั้งหมด
    // EN: Clear the current packet and release fragment memory. TH: ล้าง packet ปัจจุบันและคืนหน่วยความจำ fragment
    _sequence = // EN: Clear the active packet identifier. TH: ล้าง identifier ของ packet ปัจจุบัน
        null; // EN: Forget the active packet ID. TH: ล้าง ID packet ที่กำลังประกอบ
    _total = // EN: Clear the expected fragment total. TH: ล้างจำนวน fragment ที่คาดไว้
        0; // EN: Forget the expected fragment count. TH: ล้างจำนวน fragment ที่คาดไว้
    _bufferedBytes = // EN: Clear the tracked memory usage. TH: ล้างยอดหน่วยความจำที่ติดตามไว้
        0; // EN: Reset the memory-accounting counter. TH: ตั้งตัวนับหน่วยความจำกลับเป็นศูนย์
    _packetAge // EN: Stop the active packet timer if one exists. TH: หยุด timer ของ packet ถ้ามีอยู่
        ?.stop(); // EN: Stop timing before releasing the partial packet. TH: หยุดจับเวลาก่อนล้าง packet ที่ค้าง
    _packetAge = // EN: Release the timer reference. TH: ปล่อยตัวอ้างอิง timer
        null; // EN: Release the stale timer reference. TH: ล้างตัวอ้างอิงตัวจับเวลา
    _parts // EN: Remove all buffered fragment payloads. TH: ลบ payload fragment ที่พักไว้ทั้งหมด
        .clear(); // EN: Release every buffered fragment payload. TH: ล้าง payload fragment ที่พักไว้ทั้งหมด
  } // EN: Finish resetting assembler state. TH: จบการ reset สถานะ assembler
} // EN: Finish the bounded Doz BLE frame assembler. TH: จบตัวประกอบ BLE frame ของ Doz ที่จำกัดขนาด
