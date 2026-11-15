import 'dart:async'; // EN: Cancel HTTP response streams after deadlines. TH: ยกเลิก HTTP response stream เมื่อหมดเวลา
import 'dart:convert'; // EN: Encode JSON and validate response text. TH: เข้ารหัส JSON และตรวจข้อความ response
import 'dart:typed_data'; // EN: Buffer only the allowed response bytes. TH: buffer เฉพาะ byte response ที่อนุญาต

import 'package:flutter/foundation.dart'; // EN: Restrict diagnostics to debug builds. TH: จำกัด diagnostics ไว้เฉพาะ debug build
import 'package:http/http.dart'
    as http; // EN: Send authenticated HTTP requests. TH: ส่ง HTTP request แบบยืนยันตัวตน

import '../models/risk_result.dart'; // EN: Supply the local risk context for prompts. TH: ใช้บริบท risk ในเครื่องประกอบ prompt
import '../models/sensor_data.dart'; // EN: Supply validated sensor context for prompts. TH: ใช้บริบท sensor ที่ผ่านการตรวจประกอบ prompt

class PhratumaService {
  PhratumaService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client ==
            null; // EN: Keep injected-client ownership with the caller. TH: ให้ผู้เรียกเป็นเจ้าของ client ที่ฉีดเข้ามา

  final http.Client
      _client; // EN: Hold the injected or owned HTTP client. TH: เก็บ HTTP client ที่รับมาหรือสร้างเอง
  final bool
      _ownsClient; // EN: Track whether dispose should close the client. TH: ติดตามว่า dispose ต้องปิด client หรือไม่
  bool _disposed =
      false; // EN: Make disposal idempotent and reject later network work. TH: ทำให้ dispose เรียกซ้ำได้และปฏิเสธ network work หลังปิด

  // EN: Match the cloud API's documented request limits and bound response memory.
  // TH: ให้ตรงกับเพดาน request ของ cloud API และจำกัดหน่วยความจำ response
  static const int _maxTokenChars =
      8192; // EN: Match the API bearer-token cap. TH: ให้ตรงกับเพดาน bearer token ของ API
  static const int _maxQuestionChars =
      2000; // EN: Match the server question schema. TH: ให้ตรงกับ schema คำถามของ server
  static const int _maxPromptChars =
      10000; // EN: Match the server prompt schema. TH: ให้ตรงกับ schema prompt ของ server
  static const int _maxRequestBytes = 64 *
      1024; // EN: Match the server request-body cap. TH: ให้ตรงกับเพดาน request body ของ server
  static const int _maxResponseBytes = 32 *
      1024; // EN: Bound response memory usage. TH: จำกัดหน่วยความจำ response
  static const int _maxAnswerChars =
      8000; // EN: Bound text displayed in the chat. TH: จำกัดข้อความที่แสดงในแชต
  static const int _maxModelChars =
      128; // EN: Bound unused client model metadata. TH: จำกัด metadata รุ่นโมเดลจาก client
  static const int _maxEndpointChars =
      2048; // EN: Bound configured URL parsing and request-target size. TH: จำกัดการ parse URL และขนาด request target

  // EN: Accept only bounded printable ASCII bearer tokens before adding headers.
  // TH: รับเฉพาะ bearer token ASCII ที่พิมพ์ได้และมีความยาวจำกัดก่อนใส่ header
  static String? _safeBearerToken(String? value) {
    final token = value
        ?.trim(); // EN: Remove surrounding spaces before validation. TH: ตัดช่องว่างรอบ token ก่อนตรวจ
    if (token == null ||
        token.isEmpty ||
        token.length > _maxTokenChars ||
        token.codeUnits.any((unit) => unit <= 0x20 || unit >= 0x7f)) {
      return null; // EN: Reject malformed or oversized header credentials. TH: ปฏิเสธ credential ที่ผิดรูปหรือยาวเกิน
    }
    return token; // EN: Return only a safe printable token. TH: คืนเฉพาะ token ที่พิมพ์ได้อย่างปลอดภัย
  }

  // EN: Encode once and measure UTF-8 bytes, which is the actual HTTP body size.
  // TH: เข้ารหัสครั้งเดียวและนับ byte UTF-8 ซึ่งเป็นขนาด body ที่ส่งจริง
  static String? _boundedJson(Map<String, dynamic> value) {
    try {
      final encoded = jsonEncode(
          value); // EN: Serialize the request exactly once. TH: serialize request เพียงครั้งเดียว
      return utf8.encode(encoded).length <= _maxRequestBytes
          ? encoded
          : null; // EN: Enforce the wire-size byte cap. TH: บังคับเพดาน byte ที่ส่งจริง
    } on Object {
      return null; // EN: Reject values that cannot be serialized safely. TH: ปฏิเสธค่าที่ serialize อย่างปลอดภัยไม่ได้
    }
  }

  // EN: Read no more than the endpoint limit and reject invalid UTF-8.
  // TH: อ่านไม่เกินเพดานของ endpoint และปฏิเสธ UTF-8 ที่ผิดรูป
  static Future<String?> _readBoundedBody(
    http.StreamedResponse response, {
    required int maxBytes,
    required Duration timeout,
  }) async {
    final iterator = StreamIterator<List<int>>(response
        .stream); // EN: Keep control of cancellation on timeout. TH: ควบคุมการยกเลิก stream เมื่อ timeout
    final bytes = BytesBuilder(
        copy:
            false); // EN: Avoid another copy after bounded collection. TH: ลดการคัดลอกซ้ำหลังรวบรวมข้อมูลที่จำกัดแล้ว
    var length =
        0; // EN: Count actual response bytes. TH: นับ byte ของ response ที่รับจริง
    final stopwatch = Stopwatch()
      ..start(); // EN: Measure one total response deadline. TH: วัด deadline รวมของ response
    try {
      if (response.contentLength != null &&
          response.contentLength! > maxBytes) {
        return null; // EN: Reject oversized content before buffering; finally cancels it. TH: ปฏิเสธก่อน buffer และยกเลิก stream ใน finally
      }
      while (true) {
        // EN: Process a bounded response chunk at a time. TH: ประมวลผล response ทีละ chunk ภายใต้เพดาน
        final remaining = timeout -
            stopwatch
                .elapsed; // EN: Calculate time left before the total deadline. TH: คำนวณเวลาที่เหลือก่อน deadline รวม
        if (remaining <= Duration.zero) {
          return null; // EN: Stop when the total deadline has elapsed. TH: หยุดเมื่อหมดเวลาโดยรวม
        }
        final hasChunk = await iterator.moveNext().timeout(
            remaining); // EN: Wait only for the remaining deadline. TH: รอไม่เกินเวลาที่เหลือ
        if (!hasChunk) {
          break; // EN: Finish when the stream has no more data. TH: จบเมื่อ stream ไม่มีข้อมูลต่อ
        }
        final chunk = iterator
            .current; // EN: Access the next received byte chunk. TH: อ่าน byte chunk ที่เพิ่งได้รับ
        length += chunk
            .length; // EN: Count the received bytes before buffering. TH: นับ byte ที่รับก่อน buffer
        if (length > maxBytes) {
          return null; // EN: Reject and cancel a response over its cap. TH: ปฏิเสธและยกเลิก response ที่เกินเพดาน
        }
        bytes.add(
            chunk); // EN: Buffer only bytes that remain under the limit. TH: buffer เฉพาะ byte ที่ยังไม่เกินเพดาน
      }
      return utf8.decode(bytes.takeBytes(),
          allowMalformed:
              false); // EN: Reject malformed UTF-8. TH: ปฏิเสธ UTF-8 ที่ผิดรูป
    } on Object {
      return null; // EN: Fail closed on timeout, stream, or decoding errors. TH: ปฏิเสธเมื่อ timeout, stream หรือ decode ผิดพลาด
    } finally {
      await iterator
          .cancel(); // EN: Release the stream on every exit path. TH: ปิด stream ทุกกรณีที่ออกจากฟังก์ชัน
    }
  }

  // EN: Map server errors to safe, known diagnostics without logging arbitrary bodies.
  // TH: แปลง error server เป็นข้อความที่ปลอดภัย โดยไม่ log body ที่ไม่รู้ที่มา
  static String _safeErrorLabel(int statusCode, String? responseText) {
    if (responseText != null) {
      try {
        final decoded = jsonDecode(responseText);
        final detail =
            decoded is Map<String, dynamic> ? decoded['detail'] : null;
        if (detail is String) {
          const knownDetails = <String>{
            'Multiple Content-Length headers are not allowed.',
            'Invalid Content-Length.',
            'Content-Length does not match the received body.',
          };
          if (knownDetails.contains(detail)) return detail;
        }
      } on Object {
        // EN: Ignore malformed or untrusted response details. TH: ข้าม detail ที่ผิดรูปหรือไม่น่าเชื่อถือ
      }
    }
    if (statusCode == 400) {
      return 'Bad Request (request rejected by server/proxy)';
    }
    if (statusCode == 401) {
      return 'Unauthorized (token missing, invalid, or expired)';
    }
    if (statusCode == 413) return 'Payload Too Large';
    if (statusCode == 422) {
      return 'Validation Error (check question/prompt fields and limits)';
    }
    return 'HTTP $statusCode';
  }

  // EN: Keep correlation IDs printable and short before debug logging.
  // TH: จำกัด request ID ให้สั้นและเป็นอักขระปลอดภัยก่อน log
  static String _safeRequestId(String? value) {
    if (value == null || !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(value)) {
      return 'unavailable';
    }
    return value;
  }

  // EN: Close only the HTTP client created and owned by this service.
  // TH: ปิดเฉพาะ HTTP client ที่ service นี้สร้างและเป็นเจ้าของ
  void dispose() {
    if (_disposed) {
      // EN: Detect repeat disposal. TH: ตรวจการปิดซ้ำ
      return; // EN: Avoid closing the client more than once. TH: ป้องกันการปิด client ซ้ำ
    } // EN: Continue first-time cleanup. TH: ทำการปิดครั้งแรกต่อ
    _disposed =
        true; // EN: Mark closed before releasing the client. TH: ทำเครื่องหมายว่าปิดก่อนคืน client
    if (_ownsClient) _client.close();
  }

  static Uri? _safeChatUri(String value) {
    if (value.length > _maxEndpointChars ||
        value.codeUnits.any((unit) => unit <= 0x20 || unit == 0x7f)) {
      return null; // EN: Reject oversized URLs and control/whitespace characters. TH: ปฏิเสธ URL ยาวเกินและอักขระควบคุม/ช่องว่าง
    }
    final uri = Uri.tryParse(value
        .trim()); // EN: Parse only after the cheap size/character checks. TH: parse หลังตรวจขนาดและอักขระเบื้องต้น
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    if (path != '/chat' && !path.endsWith('/chat')) return null;
    return uri;
  }

  static bool isValidRemoteChatEndpoint(String value) =>
      _safeChatUri(value) != null;

  /// Returns the base path of the exact server the user approved for chat.
  /// For example, `https://api.example/v1/chat` becomes `https://api.example/v1`.
  static String? chatApiBaseUrl(String value) {
    final chatUri = _safeChatUri(value);
    if (chatUri == null) return null;
    final chatPath = chatUri.path.replaceFirst(RegExp(r'/+$'), '');
    final basePath = chatPath.substring(0, chatPath.length - '/chat'.length);
    return chatUri
        .replace(path: basePath)
        .toString()
        .replaceFirst(RegExp(r'/$'), '');
  }

  /// EN: Probe the matching API's Auth readiness before offering remote chat.
  /// TH: ตรวจความพร้อม Auth ของ API ปลายทางก่อนเสนอแชตระยะไกล
  Future<bool> checkReady({required String chatEndpoint}) async {
    // EN: Expose Auth-readiness rather than liveness. TH: เปิดเผยความพร้อม Auth แทนการตรวจว่า process ยังทำงาน
    if (_disposed) {
      // EN: Reject readiness probes after disposal. TH: ปฏิเสธการตรวจ readiness หลังปิด service
      return false; // EN: Do not start a request after service disposal. TH: ไม่เริ่ม request หลังปิด service
    } // EN: Continue with a live client. TH: ใช้ client ที่ยังเปิดต่อ
    final chatUri = _safeChatUri(chatEndpoint);
    if (chatUri == null) return false;
    final chatPath = chatUri.path.replaceFirst(RegExp(r'/+$'), '');
    final basePath = chatPath.endsWith('/chat')
        ? chatPath.substring(0, chatPath.length - '/chat'.length)
        : chatPath;
    final readinessUri = Uri(
      // EN: Derive a readiness route on the approved chat origin. TH: สร้าง route readiness บน origin แชตที่อนุญาต
      scheme: chatUri.scheme,
      host: chatUri.host,
      port: chatUri.hasPort ? chatUri.port : null,
      path:
          '${basePath.isEmpty ? '' : basePath}/ready', // EN: Check protected-route configuration rather than process liveness. TH: ตรวจ config ของ route ที่ป้องกันแทนแค่ดูว่า process ยังอยู่
    );

    try {
      final request = http.Request('GET',
          readinessUri) // EN: Query readiness without personal data. TH: ตรวจ readiness โดยไม่ส่งข้อมูลส่วนบุคคล
        ..followRedirects =
            false; // EN: Accept readiness only from the approved origin. TH: รับ readiness เฉพาะ origin ที่อนุมัติ
      final response = await _client.send(request).timeout(
            const Duration(seconds: 5),
          );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // EN: Log status only; readiness responses may contain deployment details.
        // TH: แสดงเฉพาะ status; response readiness อาจมีรายละเอียด deployment
        if (kDebugMode) {
          debugPrint(
              'Chat readiness check failed: HTTP ${response.statusCode}');
        }
        return false;
      }
      final responseText = await _readBoundedBody(
        response,
        maxBytes: 4096,
        timeout: const Duration(seconds: 5),
      );
      if (responseText == null) return false;
      final body = jsonDecode(responseText);
      return body is Map<String, dynamic> &&
          body['status'] ==
              'ready'; // EN: Trust only the expected readiness contract. TH: รับเฉพาะ response readiness ตามสัญญาที่กำหนด
    } catch (error) {
      // EN: Do not log the URI or any request data.
      // TH: ไม่ log URI หรือข้อมูล request
      if (kDebugMode) {
        debugPrint('Chat readiness check failed: ${error.runtimeType}');
      }
      return false;
    }
  }

  Future<String> ask({
    required String endpoint,
    required String model,
    required String userMessage,
    required SensorData sensorData,
    required RiskResult riskResult,
    required bool isLiveDeviceData,
    required bool enabled,
    required bool useMockResponse,
    String? bearerToken,
    String language = 'Thai',
  }) async {
    final isThai = language == 'Thai';
    if (_disposed) {
      // EN: Use an offline response when the service has already been closed.
      // TH: ใช้คำตอบในเครื่องเมื่อ service ถูกปิดไปแล้ว
      return _localFallback(
        userMessage,
        sensorData,
        riskResult,
        isLiveDeviceData: isLiveDeviceData,
        language: language,
      );
    }
    final token = _safeBearerToken(bearerToken);
    if (!enabled || useMockResponse || token == null) {
      // EN: Keep the remote service disabled without consent/configuration. TH: ไม่เรียก remote เมื่อปิดหรือไม่มี config/token
      return _localFallback(
        userMessage,
        sensorData,
        riskResult,
        isLiveDeviceData: isLiveDeviceData,
        language: language,
      );
    }

    final endpointUri = _safeChatUri(endpoint);
    if (endpointUri == null) {
      // EN: Reject an endpoint that is not the approved HTTPS chat route. TH: ปฏิเสธ endpoint ที่ไม่ใช่ HTTPS chat route ที่อนุมัติ
      return _localFallback(
        userMessage,
        sensorData,
        riskResult,
        isLiveDeviceData: isLiveDeviceData,
        language: language,
      );
    }

    // EN: Reject invalid field sizes locally so the API receives its documented schema.
    // TH: ปฏิเสธขนาด field ที่ผิดตั้งแต่ในแอป เพื่อให้ request ตรง schema ของ API
    if (userMessage.trim().isEmpty || userMessage.length > _maxQuestionChars) {
      // EN: Match the server's required question field and length bound. TH: ตรวจ question ให้ตรงกับ field และความยาวที่ server กำหนด
      return _localFallback(
        userMessage,
        sensorData,
        riskResult,
        isLiveDeviceData: isLiveDeviceData,
        language: language,
      );
    }
    final prompt = buildPrompt(
      userMessage: userMessage,
      sensorData: sensorData,
      riskResult: riskResult,
      isLiveDeviceData: isLiveDeviceData,
    );
    if (prompt.isEmpty || prompt.length > _maxPromptChars) {
      // EN: Avoid sending a prompt rejected by the server schema. TH: ไม่ส่ง prompt ที่ schema server จะปฏิเสธ
      return _localFallback(
        userMessage,
        sensorData,
        riskResult,
        isLiveDeviceData: isLiveDeviceData,
        language: language,
      );
    }
    if (model.trim().isEmpty || model.length > _maxModelChars) {
      // EN: Reject malformed optional model metadata before serialization. TH: ปฏิเสธ metadata model ที่ผิดรูปก่อน serialize
      return _localFallback(
        userMessage,
        sensorData,
        riskResult,
        isLiveDeviceData: isLiveDeviceData,
        language: language,
      );
    }
    final encodedBody = _boundedJson({
      'model': model,
      'question': userMessage,
      'prompt': prompt,
      'stream': false,
    });
    if (encodedBody == null) {
      return _localFallback(
        userMessage,
        sensorData,
        riskResult,
        isLiveDeviceData: isLiveDeviceData,
        language: language,
      );
    }

    try {
      final request = http.Request('POST',
          endpointUri) // EN: Use the exact approved chat route. TH: ใช้ chat route ที่อนุมัติตรงตามที่ตั้งไว้
        ..followRedirects =
            false // EN: Never forward the bearer token or chat data through redirects. TH: ห้ามส่ง bearer token หรือข้อมูลแชตผ่าน redirect
        ..headers.addAll({
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Bearer $token',
        })
        ..body = encodedBody;
      final response = await _client.send(request).timeout(
            const Duration(seconds: 18),
          );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        // EN: Read only a small bounded diagnostic body; never show/log its raw contents. TH: อ่าน body วินิจฉัยขนาดเล็กเท่านั้น ไม่แสดงหรือ log เนื้อหาดิบ
        final errorText = await _readBoundedBody(
          response,
          maxBytes: 4096,
          timeout: const Duration(seconds: 5),
        );
        // EN: Log only a safe error category and validated request ID.
        // TH: log เฉพาะหมวด error ที่ปลอดภัยและ request ID ที่ตรวจแล้ว
        if (kDebugMode) {
          final requestId = _safeRequestId(response.headers['x-request-id']);
          final errorLabel = _safeErrorLabel(response.statusCode, errorText);
          debugPrint('Remote chat failed: $errorLabel; request_id=$requestId');
        }
        return _localFallback(
          userMessage,
          sensorData,
          riskResult,
          isLiveDeviceData: isLiveDeviceData,
          language: language,
        );
      }

      final responseText = await _readBoundedBody(
        response,
        maxBytes: _maxResponseBytes,
        timeout: const Duration(seconds: 5),
      );
      if (responseText == null) {
        return _localFallback(
          userMessage,
          sensorData,
          riskResult,
          isLiveDeviceData: isLiveDeviceData,
          language: language,
        );
      }
      final decoded = jsonDecode(responseText);
      if (decoded is! Map<String, dynamic>) {
        return _localFallback(
          userMessage,
          sensorData,
          riskResult,
          isLiveDeviceData: isLiveDeviceData,
          language: language,
        );
      }
      final body = decoded;
      final rawAnswer = body['answer'] ?? body['response'];
      if (rawAnswer is! String || rawAnswer.length > _maxAnswerChars) {
        return _localFallback(
          userMessage,
          sensorData,
          riskResult,
          isLiveDeviceData: isLiveDeviceData,
          language: language,
        );
      }
      final answer = rawAnswer.trim();
      if (answer.isEmpty) {
        return _localFallback(
          userMessage,
          sensorData,
          riskResult,
          isLiveDeviceData: isLiveDeviceData,
          language: language,
        );
      }
      if (body['mode'] == 'fallback') {
        final source = isThai
            ? 'คำตอบสำรองจากระบบความรู้ (ไม่ใช่คำตอบจากโมเดล AI)'
            : 'Knowledge fallback (not generated by the AI model)';
        return '$source:\n$answer';
      }
      // Accept only the backend's explicit LLM mode. Unknown/missing modes
      // must not be presented as model-generated replies.
      if (body['mode'] != 'llm') {
        return _localFallback(
          userMessage,
          sensorData,
          riskResult,
          isLiveDeviceData: isLiveDeviceData,
          language: language,
        );
      }
      return answer;
    } catch (error) {
      // EN: Keep the bearer token, URL, prompt, and sensor data out of logs.
      // TH: ไม่ log bearer token, URL, prompt หรือข้อมูลเซนเซอร์
      if (kDebugMode) {
        debugPrint('Remote chat failed: ${error.runtimeType}');
      }
      return _localFallback(
        userMessage,
        sensorData,
        riskResult,
        isLiveDeviceData: isLiveDeviceData,
        language: language,
      );
    }
  }

  String _localFallback(
    String userMessage,
    SensorData sensorData,
    RiskResult riskResult, {
    required bool isLiveDeviceData,
    required String language,
  }) {
    final isThai = language == 'Thai';
    final source = isThai
        ? 'คำตอบช่วยเหลือในเครื่อง (ไม่ได้สร้างโดย AI ระยะไกล)'
        : 'Local help (not generated by remote AI)';
    final answer = fallbackAnswer(
      userMessage,
      sensorData,
      riskResult,
      isLiveDeviceData: isLiveDeviceData,
      language: language,
    );
    return '$source:\n$answer';
  }

  String buildPrompt({
    required String userMessage,
    required SensorData sensorData,
    required RiskResult riskResult,
    required bool isLiveDeviceData,
  }) {
    final String dataContext;
    if (!isLiveDeviceData) {
      dataContext =
          '''There is no confirmed live reading from the physical device.
Any cached or demo values must not be described as real measurements. Do not infer a current risk or vital signs.''';
    } else if (sensorData.rawRed != null || sensorData.rawIr != null) {
      dataContext = '''Live raw telemetry only:
Red ADC mean: ${sensorData.rawRed ?? 'unavailable'} (raw counts)
IR ADC mean: ${sensorData.rawIr ?? 'unavailable'} (raw counts)
Accelerometer mean: ${sensorData.accelX.toStringAsFixed(3)}, ${sensorData.accelY.toStringAsFixed(3)}, ${sensorData.accelZ.toStringAsFixed(3)} m/s²
Gyroscope mean: ${sensorData.gyroX.toStringAsFixed(2)}, ${sensorData.gyroY.toStringAsFixed(2)}, ${sensorData.gyroZ.toStringAsFixed(2)} °/s
This firmware does not provide heart rate, SpO2, GSR, skin temperature, or an AI risk result. Do not infer these values from raw telemetry.''';
    } else {
      dataContext = '''Confirmed live device metrics:
Heart Rate: ${sensorData.heartRate} BPM
SpO2: ${sensorData.spo2} %
GSR: ${sensorData.gsr.toStringAsFixed(1)}
Temperature: ${sensorData.temperature.toStringAsFixed(1)} °C
Motion Magnitude: ${sensorData.motionMagnitude.toStringAsFixed(2)}
Gyro Magnitude: ${sensorData.gyroMagnitude.toStringAsFixed(2)}

Device risk analysis:
Risk Class: ${riskResult.riskClass}
Alert Level: ${riskResult.alertLevel}
Detected Signs: ${riskResult.detectedSigns.join(', ')}
Recommendation: ${riskResult.recommendation}''';
    }
    final sections = <String>[
      '''
You are doz AI Health Monitoring Assistant.
Explain Risk Detection and Early Warning results in simple language.
Provide safety recommendations and user guidance.
Never invent measurements or claim the prototype makes a medical diagnosis.

$dataContext
''',
      '''User question:
$userMessage

Use simple language.
Give clear and safe advice.
If alert level is Emergency, recommend stopping activity and contacting emergency support if symptoms continue.
''',
    ];
    return sections.join('\n\n');
  }

  String fallbackAnswer(
      String userMessage, SensorData sensorData, RiskResult riskResult,
      {required bool isLiveDeviceData, String language = 'Thai'}) {
    final isThai = language == 'Thai';
    final localHelp = _localHelpAnswer(userMessage, isThai: isThai);
    if (localHelp != null) {
      final String dataNotice;
      if (!isLiveDeviceData) {
        dataNotice = isThai
            ? 'ยังไม่มีข้อมูลสดจากอุปกรณ์จริง จึงไม่สามารถประเมินค่าสุขภาพปัจจุบันได้\n\n'
            : 'No live readings from a physical device are available, so current health cannot be assessed.\n\n';
      } else if (sensorData.rawRed != null || sensorData.rawIr != null) {
        dataNotice = isThai
            ? 'ขณะนี้อุปกรณ์ส่งเฉพาะ raw telemetry และยังไม่มี HR, SpO₂ หรือผล AI\n\n'
            : 'The device currently sends raw telemetry only; HR, SpO₂, and AI results are unavailable.\n\n';
      } else {
        dataNotice = '';
      }
      return '$dataNotice$localHelp';
    }
    if (!isLiveDeviceData) {
      return isThai
          ? 'ยังไม่มีข้อมูลสดจากอุปกรณ์จริงในขณะนี้ คำตอบนี้จึงไม่ประเมินค่าชีพจร SpO₂ หรือระดับความเสี่ยง โปรดเชื่อมต่ออุปกรณ์และรอรับข้อมูลก่อน หากต้องการ ฉันช่วยอธิบายวิธีใช้แอปหรือข้อมูลทั่วไปได้'
          : 'There are no live readings from a physical device, so I cannot assess heart rate, SpO₂, or current risk. Connect the device and wait for readings. I can still explain how to use the app or answer general questions.';
    }
    if (sensorData.rawRed != null || sensorData.rawIr != null) {
      return isThai
          ? 'อุปกรณ์กำลังส่ง raw telemetry (Red ADC ${sensorData.rawRed ?? 'ไม่มีข้อมูล'}, IR ADC ${sensorData.rawIr ?? 'ไม่มีข้อมูล'}) แต่ firmware รุ่นนี้ยังไม่ส่งผล HR, SpO₂ หรือ AI risk จึงยังสรุปสถานะสุขภาพจากข้อมูลชุดนี้ไม่ได้'
          : 'The device is sending raw telemetry (Red ADC ${sensorData.rawRed ?? 'unavailable'}, IR ADC ${sensorData.rawIr ?? 'unavailable'}), but this firmware does not provide HR, SpO₂, or an AI risk result. Health status cannot be assessed from these values.';
    }
    final values =
        'Heart Rate ${sensorData.heartRate} BPM, SpO2 ${sensorData.spo2}%, GSR ${sensorData.gsr.toStringAsFixed(1)}, Temperature ${sensorData.temperature.toStringAsFixed(1)}°C';
    if (riskResult.alertLevel == 'Emergency') {
      return isThai
          ? 'doz ตรวจพบ ${riskResult.riskClass} ระดับฉุกเฉิน ค่าที่เกี่ยวข้อง: $values หยุดกิจกรรมและอยู่ในที่ปลอดภัย หากอาการยังต่อเนื่องให้โทร 1669'
          : 'doz detected ${riskResult.riskClass} at Emergency level. Contributing values: $values. Stop activity, move to a safe place, and call emergency services if the condition continues.';
    }
    if (riskResult.alertLevel == 'Warning') {
      return isThai
          ? 'doz ตรวจพบ ${riskResult.riskClass} ระดับเตือน เนื่องจาก ${riskResult.detectedSigns.join(', ')} ค่าที่เกี่ยวข้อง: $values คำแนะนำ: ${riskResult.recommendation}'
          : 'doz detected ${riskResult.riskClass} at Warning level because ${riskResult.detectedSigns.join(', ')}. Contributing values: $values. Recommended action: ${riskResult.recommendation}';
    }
    return isThai
        ? 'สถานะติดตามสุขภาพปัจจุบันคือ ${riskResult.riskClass} ระดับ ${riskResult.alertLevel} ค่าที่เกี่ยวข้อง: $values คำแนะนำ: ${riskResult.recommendation}'
        : 'Current health-monitoring status is ${riskResult.riskClass} at ${riskResult.alertLevel}. Contributing values: $values. Recommended action: ${riskResult.recommendation}';
  }

  String? _localHelpAnswer(String userMessage, {required bool isThai}) {
    final q = userMessage.toLowerCase();
    if (RegExp(
            r'bluetooth|\bble\b|\bconnect(?:ion)?\b|\bpair(?:ing)?\b|\bscan(?:ning)?\b|device not found|disconnect|เชื่อมต่อ|จับคู่|ค้นหาอุปกรณ์')
        .hasMatch(q)) {
      return isThai
          ? 'วิธีเชื่อมต่อ: เปิดบอร์ดให้โฆษณา BLE, เปิด Bluetooth บนโทรศัพท์, ไปที่หน้า “อุปกรณ์” แล้วกดค้นหา จากนั้นเลือก Doz-ESP32S3 และอนุญาตสิทธิ์เมื่อระบบถาม ไม่ต้องจับคู่จาก Bluetooth Settings ให้เชื่อมในแอป หากเคยปฏิเสธสิทธิ์ ให้เปิดการตั้งค่าแอปแล้วอนุญาต Bluetooth/อุปกรณ์ใกล้เคียง'
          : 'To connect: power on the board and make sure it is advertising over BLE. Turn on Bluetooth, open the Devices page, tap Find nearby devices, then select Doz-ESP32S3 and grant permission if prompted. Do not pair in system Bluetooth Settings; connect in the app. If permission was denied, enable Bluetooth/Nearby Devices in app settings.';
    }
    if (RegExp(
            r'download|install|play store|app store|testflight|ดาวน์โหลด|ติดตั้ง|แอปสโตร์')
        .hasMatch(q)) {
      return isThai
          ? 'สถานะการแจกจ่ายตอนนี้: มีเฉพาะ Android debug APK สำหรับทดสอบและติดตั้งแบบ sideload ยังไม่ใช่รุ่น Play Store ส่วน iOS ยังไม่มี build ที่ยืนยันและแจกผ่าน TestFlight ได้ โปรดใช้เฉพาะไฟล์จากโฟลเดอร์โปรเจกต์ที่ผู้พัฒนาส่งให้ และอย่าติดตั้ง APK จากแหล่งที่ไม่รู้จัก'
          : 'Distribution status: an Android debug APK is available for sideload testing; it is not a Play Store release. An iOS build has not yet been verified or distributed through TestFlight. Use only the APK supplied by the project developer, not files from unknown sources.';
    }
    if (RegExp(
            r'forgot.*password|reset.*password|password reset|ลืมรหัส|กู้.*รหัส|ตั้งรหัสผ่านใหม่')
        .hasMatch(q)) {
      return isThai
          ? 'ที่หน้าเข้าสู่ระบบ กรอกอีเมลแล้วกด “ลืมรหัสผ่าน” จากนั้นเปิดลิงก์ในอีเมลเพื่อกำหนดรหัสใหม่ หากลิงก์ไม่เปิดแอปหรือหมดอายุ ต้องตรวจ Supabase redirect allowlist ให้มี doz://login-callback/ และขอลิงก์ใหม่; อย่าส่งรหัสผ่านหรือ recovery link ให้ผู้อื่น'
          : 'On the sign-in screen, enter your email and choose “Forgot password”, then use the email link to set a new password. If the link does not open the app or has expired, verify the Supabase redirect allowlist includes doz://login-callback/ and request a new link. Do not share passwords or recovery links.';
    }
    if (RegExp(
            r'max30102|\bred\b|infrared|\bir\b|spo.?2|ออกซิเจน|ชีพจร|heart.?rate|\bhr\b')
        .hasMatch(q)) {
      return isThai
          ? 'MAX30102 ให้สัญญาณแสง Red และ IR เป็นค่า ADC ดิบ ไม่ใช่ค่า HR หรือ SpO₂ โดยตรง เฟิร์มแวร์ที่เชื่อมอยู่ยังไม่คำนวณ HR/SpO₂ จึงไม่ควรแปลค่า ADC เป็นค่าชีพจรหรือออกซิเจน'
          : 'MAX30102 provides raw Red and IR optical ADC counts; these are not HR or SpO₂ values. The connected firmware does not yet calculate HR/SpO₂, so do not interpret ADC counts as pulse or oxygen measurements.';
    }
    if (RegExp(r'แบต|battery|เปอร์เซ็นต์แบต').hasMatch(q)) {
      return isThai
          ? 'เฟิร์มแวร์ BLE ปัจจุบันยังไม่ส่งเปอร์เซ็นต์แบตเตอรี่ แอปจะแสดง “—” แทนการคาดเดา ต้องเพิ่มการวัดแรงดันแบตเตอรี่และฟิลด์ battery ในโปรโตคอลก่อนจึงจะแสดงได้'
          : 'The current BLE firmware does not send battery percentage, so the app shows “—” rather than guessing. Battery-voltage measurement and a battery field must be added to the protocol before the app can display it.';
    }
    if (RegExp(
            r'mpu.?6050|accelerometer|gyroscope|\bimu\b|ความเร่ง|ไจโร|อุณหภูมิ.*ชิป|chip temperature')
        .hasMatch(q)) {
      return isThai
          ? 'MPU6050 วัดความเร่ง 3 แกนและอัตราการหมุน 3 แกน; แอปรับค่าเฉลี่ย accelerometer เป็น m/s² และ gyroscope เป็น °/s จากเฟิร์มแวร์ปัจจุบัน ค่าอุณหภูมิภายในชิป MPU6050 ไม่ใช่อุณหภูมิผิวหนัง และเฟิร์มแวร์นี้ยังไม่ส่งค่าอุณหภูมิ'
          : 'The MPU6050 measures 3-axis acceleration and angular rate. The current firmware sends mean accelerometer values in m/s² and gyroscope values in °/s. Its internal chip temperature is not skin temperature, and this firmware does not send temperature.';
    }
    if (RegExp(
            r'delete\s+(my\s+)?account|remove\s+(my\s+)?account|account deletion|ลบบัญชี|ลบบัญชีผู้ใช้')
        .hasMatch(q)) {
      return isThai
          ? 'การลบบัญชีต้องเข้าสู่ระบบและให้ API ที่ตั้งค่าไว้ยืนยันการลบก่อน หากยังไม่ได้ตั้งค่า API หรือเซิร์ฟเวอร์ลบไม่สำเร็จ แอปจะไม่ลบบัญชีหรือข้อมูลในเครื่อง และจะแจ้งว่าไม่สำเร็จ เมื่อเซิร์ฟเวอร์ยืนยันแล้ว แอปจึงลบบัญชีและข้อมูลที่เกี่ยวข้อง รวมถึงโปรไฟล์และประวัติในเครื่องของบัญชีนั้น การลบถาวรย้อนกลับไม่ได้'
          : 'Account deletion requires you to be signed in and the configured API to confirm deletion first. If the API is not configured or the server fails, the app does not delete the account or local data and reports failure. Only after server confirmation does the app remove the account and associated data, including that account’s local profile and alert history. Permanent deletion cannot be undone.';
    }
    if (RegExp(r'ประวัติ|history|export|ส่งออก|csv|ลบข้อมูล|delete')
        .hasMatch(q)) {
      return isThai
          ? 'ส่งออก sensor buffer ได้จากหน้า Profile → Export sensor history CSV; buffer เก็บในหน่วยความจำสูงสุด 240 readings ส่วนปุ่มลบจะลบ alert history และล้าง buffer แต่ไม่ลบโปรไฟล์หรือบัญชี'
          : 'Export the sensor buffer from Profile → Export sensor history CSV. The in-memory buffer holds up to 240 readings. The delete action clears alert history and the buffer, but does not delete the profile or account.';
    }
    if (RegExp(
            r'privacy|personal data|data.*(?:store|keep|collect)|(?:store|keep|collect).*data|stored|storage|upload|\bcloud\b|sent to|ความเป็นส่วนตัว|ข้อมูลเก็บ|เก็บข้อมูล|เก็บไว้|ข้อมูลของฉัน|ส่งข้อมูล|คลาวด์')
        .hasMatch(q)) {
      return isThai
          ? 'ค่า sensor ที่แสดงเก็บเป็น buffer ชั่วคราวในหน่วยความจำ สูงสุด 240 readings; ประวัติการแจ้งเตือนและโปรไฟล์เก็บในเครื่อง ส่วน cloud health-data sync ปิดอยู่ หากใช้ chatbot ระยะไกล ระบบจะขออนุญาตก่อนส่งคำถามและข้อมูลสดที่เกี่ยวข้องไปยัง endpoint ที่ตั้งค่าไว้ หากไม่อนุญาตจะใช้คำตอบในเครื่อง'
          : 'Displayed sensor readings are held in a temporary in-memory buffer of up to 240 readings. Alert history and profile data are stored locally; cloud health-data sync is disabled. Remote chat asks for consent before sending your question and relevant live data to the configured endpoint. Without consent, the app uses local answers.';
    }
    if (RegExp(r'login|log in|sign.?in|บัญชี|เข้าสู่ระบบ|สมัคร').hasMatch(q)) {
      return isThai
          ? 'ระบบบัญชีใช้ Supabase Auth เมื่อผู้พัฒนาตั้งค่า URL และ publishable key ให้ครบ หากหน้าจอแจ้งว่าตั้งค่าบัญชีไม่สำเร็จ ต้องตรวจสองค่านี้และ build แอปใหม่; โหมด local demo ไม่ได้ยืนยันตัวตน'
          : 'Accounts use Supabase Auth after the developer configures the project URL and publishable key. If the app reports an Auth configuration error, verify both values and rebuild. Local demo mode does not authenticate users.';
    }
    if (RegExp(r'ai|model|โมเดล|วิเคราะห์|prediction|ทำนาย').hasMatch(q)) {
      return isThai
          ? 'อุปกรณ์และเฟิร์มแวร์ที่เชื่อมอยู่ตอนนี้ส่ง raw sensor telemetry แต่ยังไม่มี AI inference ในบอร์ด แอปจะแสดง “AI analysis unavailable” และไม่ควรตีความว่า Safe หรือใช้เพื่อวินิจฉัย'
          : 'The connected device and firmware currently send raw sensor telemetry without on-device AI inference. The app shows “AI analysis unavailable”; do not interpret this as Safe or use it for diagnosis.';
    }
    return null;
  }
}
