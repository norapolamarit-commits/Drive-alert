# doz — Privacy Notice Draft

> Generated from `lib/legal/privacy_policy_draft.dart`; edit the source constants, then rerun this script to refresh this copy.

## Thai

doz — ร่างประกาศความเป็นส่วนตัวสำหรับแอปต้นแบบ
ฉบับร่าง 1.1 | ปรับปรุง 11 พฤศจิกายน 2569

สำคัญ: เอกสารนี้เป็นร่างเพื่อทบทวน ไม่ใช่คำรับรองว่าแอปปฏิบัติตามกฎหมายครบถ้วน ผู้พัฒนาต้องระบุผู้ควบคุมข้อมูล ผู้ประมวลผล ช่องทางติดต่อ ระยะเวลาเก็บ และตรวจทานกับผู้เชี่ยวชาญก่อนเผยแพร่

1. แอปนี้ทำอะไร
doz เป็นต้นแบบเชื่อมต่ออุปกรณ์ ESP32 ผ่าน Bluetooth Low Energy (BLE) เพื่อแสดงข้อมูลจากเซนเซอร์และสถานะที่อุปกรณ์ส่งมา แอปไม่ใช่เครื่องมือแพทย์ ไม่วินิจฉัยโรค และไม่ควรใช้แทนคำแนะนำจากบุคลากรทางการแพทย์

2. ข้อมูลที่อาจประมวลผล
ข้อมูลโปรไฟล์ที่ผู้ใช้เลือกกรอก เช่น ชื่อ อายุ เพศ ส่วนสูง น้ำหนัก ภาวะสุขภาพ และผู้ติดต่อฉุกเฉิน โดยข้อมูลสุขภาพเสริมไม่จำเป็นต่อการเริ่มใช้และยังไม่ถูกใช้โดยการแสดงผล/วิเคราะห์เซนเซอร์ปัจจุบัน; ค่าจากเซนเซอร์/สถานะความเสี่ยง/ประวัติการแจ้งเตือน; ตัวระบุอุปกรณ์และสถานะ BLE; ตำแหน่งเมื่อผู้ใช้กดอนุญาตและเรียกใช้ฟังก์ชันตำแหน่งเท่านั้น ข้อมูลสาธิตในโหมดทดลองไม่ใช่ข้อมูลจากอุปกรณ์จริง

บน Android รุ่นเก่าบางรุ่น ระบบปฏิบัติการอาจกำหนดให้แอปขอ Location permission เพื่อค้นหาอุปกรณ์ BLE; การอนุญาตนี้ใช้สำหรับขั้นตอน scan และแอปไม่อ่านหรือส่งพิกัดจากการ scan ดังกล่าว การอ่านตำแหน่งจริงเป็นฟังก์ชันแยก ซึ่งจะทำเมื่อผู้ใช้เรียกใช้และอนุญาตเท่านั้น

3. บัญชีและการเก็บในเครื่อง
เมื่อเปิดใช้ระบบบัญชี แอปใช้ Supabase Auth สำหรับสมัคร/เข้าสู่ระบบด้วยอีเมล ลิงก์ยืนยัน และกู้คืนรหัสผ่าน ผู้ให้บริการได้รับอีเมลและข้อมูลที่จำเป็นต่อการยืนยันตัวตน รหัสผ่านไม่ได้ถูกบันทึกในโปรไฟล์แอป ส่วน session ถูกจัดการโดย SDK ของผู้ให้บริการ ข้อมูลโปรไฟล์และประวัติสุขภาพในรุ่นนี้ยังเก็บในเครื่อง โดยแยกคีย์ตามบัญชีเพื่อป้องกันการแสดงข้ามบัญชี แต่เป็นเพียงการแยกเชิงแอป ไม่ใช่การเข้ารหัสข้อมูลสุขภาพ

ตัวอย่างจากเซนเซอร์ที่แสดงเป็นประวัติระหว่าง session เก็บในหน่วยความจำของแอป จำกัดไม่เกิน 240 readings และไม่ใช่ประวัติถาวร ส่วน alert history เก็บในเครื่อง ผู้ใช้ส่งออก sensor buffer ที่ยังอยู่ในหน่วยความจำเป็น CSV และลบ alert history พร้อมล้าง buffer ได้ การลบนี้ไม่ลบโปรไฟล์หรือบัญชี

ข้อความสนทนาใน chatbot แสดงอยู่ในหน่วยความจำของแอปและไม่มีการบันทึกเป็นประวัติถาวรในเครื่อง เมื่อออกจากบัญชี แอปรีเซ็ตหน้าสนทนาในหน่วยความจำ หากใช้ chatbot ระยะไกล คำถามและ prompt ที่อธิบายด้านล่างจะถูกส่งไปยัง endpoint ที่ตั้งค่าไว้ตามความยินยอม; การไม่บันทึกประวัติในแอปไม่ได้หมายความว่าเซิร์ฟเวอร์หรือผู้ให้บริการปลายทางไม่ประมวลผลหรือไม่เก็บ log

พิกัดที่ผู้ใช้ร้องขอจะเก็บใน secure storage ของบัญชีบนอุปกรณ์ จนกว่าผู้ใช้จะกด “ลบตำแหน่งที่บันทึกไว้” ใน โปรไฟล์ > ตั้งค่าอุปกรณ์ หรือลบบัญชี พิกัดเป็นตัวเลือก ไม่จำเป็นต่อ BLE และไม่ถูกส่งไปกับคำถาม chatbot ตามคำขอปัจจุบัน

เมื่อลงชื่อออก แอปนำข้อมูลโปรไฟล์และข้อมูลสุขภาพที่กำลังแสดงออกจากหน่วยความจำ และยกเลิกการเชื่อมต่อ BLE; อย่างไรก็ตาม โปรไฟล์/การตั้งค่าและ alert history ที่เก็บไว้ในเครื่องยังคงอยู่ภายใต้คีย์ของบัญชีนั้น เพื่อให้ใช้ต่อได้เมื่อลงชื่อเข้าบัญชีเดิม การลงชื่อออกไม่ใช่การลบข้อมูลในเครื่องหรือการลบบัญชี

มี flow ขอและยืนยันลบบัญชีในแอปและ endpoint DELETE /account แล้ว แต่ยังใช้ลบจริงไม่ได้จนกว่าจะ deploy Cloud API พร้อมตั้งค่า SUPABASE_SERVICE_ROLE_KEY ฝั่ง server และทดสอบกับโครงการทดสอบก่อน หาก server ยังไม่พร้อม การลบจะล้มเหลวและแอปจะไม่ลบข้อมูลในเครื่องโดยอ้างว่าสำเร็จ การถอนการติดตั้งอาจลบข้อมูลในเครื่อง แต่ไม่ใช่วิธีลบบัญชี

ปัจจุบัน cloud sync สำหรับข้อมูลสุขภาพถูกปิดไว้ในแอป และ Cloud API ปฏิเสธ route อ่าน/เขียนข้อมูลสุขภาพด้วย HTTP 503 เว้นแต่ผู้ดูแลจะตั้ง `HEALTH_DATA_SYNC_ENABLED=true` ฝั่ง server หลังผ่านการทบทวนก่อน ข้อมูล sensor/alert จึงไม่ถูกส่งเป็น event จากแอปและไม่ควรถูกจัดเก็บผ่าน route เหล่านี้ในการตั้งค่าปัจจุบัน หากเปิด sync ในอนาคต แอปจะส่งข้อมูลเซนเซอร์ ผลความเสี่ยง สถานะอุปกรณ์ และเฉพาะ device ID; server ระบุ user ID จาก token ที่ยืนยันแล้ว และไม่ส่งชื่อ อายุ เพศ หรือลักษณะสุขภาพจากโปรไฟล์ไปกับ event ตัวอย่าง API เก็บในหน่วยความจำหรือใช้ Firestore ได้ตาม deployment; ระยะเวลาเก็บและการลบจริงยังต้องกำหนดและตรวจสอบก่อนเปิดใช้

เมื่อใช้ chatbot หรือคำแนะนำ AI ระยะไกล ขณะเข้าสู่ระบบและหลังให้ความยินยอม คำถามและ prompt ที่สร้างจากสถานะปัจจุบันจะถูกส่งผ่าน HTTPS ไปยัง endpoint ที่ตั้งค่าไว้ โดยแนบ access token ให้เซิร์ฟเวอร์ตรวจสอบบัญชี เมื่อเชื่อมกับ firmware สตรีมปัจจุบัน prompt อาจมีค่าเฉลี่ย Red/IR ในหน่วย raw ADC counts จาก MAX30102 และค่าเฉลี่ย accelerometer (m/s²) กับ gyroscope (°/s) จาก MPU6050 ซึ่งแอปแปลงจาก raw counts ก่อนส่ง; firmware นี้ยังไม่ให้ HR, SpO₂ หรือผล AI แอปจะระบุเมื่อไม่มีข้อมูลสดและไม่ควรตีความค่า demo/cached ว่าเป็นค่าจากอุปกรณ์ แอปไม่แนบชื่อ อายุ เพศ หรือประวัติแจ้งเตือนในคำขอนี้ หากเปิด LLM บนเซิร์ฟเวอร์ อาจส่งต่อ prompt ไปยังผู้ให้บริการโมเดลภายนอกซึ่งอาจประมวลผลนอกประเทศไทย การยืนยันตัวตนไม่ได้รับรองการเก็บรักษาข้อมูลของเซิร์ฟเวอร์หรือผู้ให้บริการ อย่าป้อนข้อมูลจริงหรือข้อมูลอ่อนไหวในรุ่นทดลองจนกว่าจะตรวจสอบผู้ให้บริการและมาตรการแล้ว

หลังยินยอม แอปอาจส่งคำขอ HTTPS แบบ GET ไปยัง `/health` ของ endpoint เดียวกันเพื่อตรวจว่าเซิร์ฟเวอร์ตอบสนองหรือไม่ คำขอนี้ไม่มี access token คำถาม หรือข้อมูลเซนเซอร์ อย่างไรก็ตาม ผู้ให้บริการเซิร์ฟเวอร์ โฮสติ้ง หรือเครือข่ายอาจเห็น IP address เวลา และ metadata ของคำขอ; การเก็บ log และระยะเวลาเก็บขึ้นกับผู้ให้บริการ ซึ่งยังต้องตรวจสอบก่อนเผยแพร่

4. วัตถุประสงค์และทางเลือก
ใช้ข้อมูลเพื่อแสดงผล/ทดสอบการเชื่อมต่อ วิเคราะห์สถานะต้นแบบ จัดการประวัติและการแจ้งเตือน และตอบคำถามผ่าน chatbot เมื่อเปิดใช้งาน ผู้ใช้ปฏิเสธการให้ตำแหน่งได้โดยยังใช้ BLE ได้ การใช้ cloud/AI ต้องแยกเป็นความยินยอมที่เลือกได้ ไม่รวมกับการใช้ข้อมูลในเครื่อง และผู้ใช้ปิดความยินยอม AI ระยะไกลได้จากหน้าคุย

5. ความปลอดภัยและระยะเวลาเก็บ
โปรไฟล์ส่วนบุคคล/สุขภาพ พิกัด และประวัติแจ้งเตือนในเครื่องใช้ secure storage ของแพลตฟอร์ม (เช่น Keychain/Keystore ตามระบบปฏิบัติการ) และแยก key ตามบัญชี; ข้อมูลเซนเซอร์ต่อเนื่องอยู่ในหน่วยความจำของแอปและไม่ถูกบันทึกในเครื่องโดยเส้นทางปัจจุบัน การเข้าถึง การสำรอง/ลบข้อมูล และระยะเวลาเก็บฝั่งผู้ให้บริการยังขึ้นกับการตั้งค่าอุปกรณ์และ Supabase project ต้องตรวจบนอุปกรณ์จริงก่อนเผยแพร่

6. สิทธิและการติดต่อ
ผู้ใช้สามารถขอลบบัญชีจากแอปได้เมื่อบริการลบบัญชีฝั่ง server ถูกตั้งค่าและพร้อมใช้งาน การยืนยันสำเร็จจะลบบัญชี Supabase, ข้อมูล sensor/alert ที่ผูกกับบัญชีใน Cloud API/Firestore และข้อมูลโปรไฟล์/ประวัติ alert ในเครื่องของบัญชีนั้น หาก server ไม่พร้อม แอปจะแจ้งว่าลบไม่สำเร็จและจะไม่ลบข้อมูลในเครื่องโดยอ้างว่าลบสำเร็จ การลบนี้ไม่รับประกันการลบข้อมูลที่ผู้ให้บริการภายนอกเก็บตามนโยบายของตน ผู้ใช้ยังติดต่อผู้พัฒนาได้ที่ norapolamarit@gmail.com และส่งออก sensor buffer ในหน่วยความจำเป็น CSV ก่อนลบได้

7. เด็กและผู้เยาว์
ยังไม่มีระบบตรวจสอบอายุหรือกลไกยืนยันผู้ปกครอง จึงไม่ควรเปิดใช้กับผู้เยาว์จนกว่าจะมีการประเมินข้อกำหนดและออกแบบขั้นตอนที่เหมาะสม

8. การเปลี่ยนแปลง
เมื่อมีการเปลี่ยนแปลงสาระสำคัญ ผู้พัฒนาจะปรับเลขฉบับและแจ้งให้ผู้ใช้ทราบตามช่องทางที่จัดทำขึ้น

---

## English

doz — Prototype Privacy Notice (Draft)
Draft 1.1 | Updated 11 November 2026

IMPORTANT: This is a review draft, not a statement of legal compliance. Before public release, identify the data controller and processors, contact details, retention periods, and obtain qualified legal review.

1. What the app does
doz is a prototype companion for an ESP32 wearable. It connects over Bluetooth Low Energy (BLE) to display sensor data and device-provided status. It is not a medical device, does not diagnose disease, and is not a substitute for professional medical advice.

2. Data that may be processed
Optional user-entered profile information (for example name, age, gender, height, weight, health conditions, and emergency contact); optional health profile details are not required to start and are not used by the current sensor display/analysis. Other data may include sensor values, risk status, and alert history; device identifiers and BLE status; and location only when the user grants permission and invokes a location feature. Demo/mock values are not readings from a physical device.

On some older Android versions, the operating system may require Location permission to scan for BLE devices. That permission is used for the scan step; the app does not read or send coordinates from that scan. Actual location is a separate feature and is accessed only when the user invokes it and grants permission.

3. Accounts and on-device storage
When account mode is configured, the app uses Supabase Auth for email/password sign-up and sign-in, email confirmation, and password recovery. The provider processes the email and authentication data required to operate the account. The app does not save the password in its profile store; the provider SDK manages the session. Profile and health history remain on-device in platform secure storage with account-scoped keys.

Sensor samples shown in session history are held in app-process memory, capped at 240 readings, and are not a persistent history. Alert history is stored locally. Users can export the in-memory sensor buffer to CSV and delete local alert history while clearing that buffer; this does not delete the profile or account.

Chatbot conversation messages are kept in app-process memory and are not saved as persistent on-device chat history. The in-memory conversation is reset on sign-out. If remote chatbot is used, the question and prompt described below are still sent to the configured endpoint under the user's consent; the lack of an in-app saved history does not mean the server or downstream provider does not process or retain logs.

Location coordinates explicitly requested by the user are stored in that account's platform secure storage until the user selects “Clear saved location” in Profile > Device settings or deletes the account. Location is optional, not needed for BLE, and is not included with chatbot questions in the current request.

On sign-out, the app clears profile and health data from active memory and disconnects BLE. Locally stored profile/settings and alert history remain under that account's local storage scope so they can be restored on the same device after signing in again. Sign-out does not delete local data or the account.

The app includes an account-deletion request and confirmation flow plus a `DELETE /account` endpoint, but deletion is not operational until the Cloud API is deployed with the server-only `SUPABASE_SERVICE_ROLE_KEY` and tested in a non-production project. A confirmed deletion is intended to remove the Supabase account, associated Cloud API/Firestore sensor and alert records, and that account's local profile and alert-history preferences. If the server is unavailable or unconfigured, the app reports failure and does not claim local deletion succeeded. This does not guarantee deletion of data retained by external providers under their own policies. Users may contact norapolamarit@gmail.com and can export the in-memory sensor buffer before deletion. Uninstalling may remove on-device data but does not delete the account.

Cloud health-data sync is currently disabled in the app, and the Cloud API rejects health-data read/write routes with HTTP 503 unless an operator explicitly sets `HEALTH_DATA_SYNC_ENABLED=true` on the server after review. Sensor and alert event payloads are therefore not sent by the app's sync functions or accepted by those routes under the current configuration. If the developer enables this in a future version, sensor values, risk results, device state, and only the device ID are sent; the server derives the user ID from the verified token. The app does not send the user's name, age, gender, or health details from the profile with these events. The example API stores data in memory or can use Firestore depending on deployment; retention and deletion must be defined and verified before enabling it.

When remote chatbot or AI advice is used while signed in and after consent, the question and a prompt derived from current status are sent over HTTPS to the configured endpoint with an access token for server-side account verification. With the current streaming firmware, the prompt may include mean Red/IR raw ADC counts from MAX30102 and mean accelerometer (m/s²) and gyroscope (°/s) values from MPU6050; the app converts the IMU raw counts before including them. This firmware does not provide heart rate, SpO₂, or AI results. The app distinguishes missing live data and must not describe demo/cached values as device readings. The app does not include the user's name, age, gender, or alert history in this request. If a server-side LLM is enabled, the server may forward the prompt to an external model provider, potentially outside Thailand. Authentication does not establish that the server or provider meets data-retention or security requirements. Do not enter real or sensitive data in this prototype until the providers and safeguards are reviewed.

After consent, the app may also make an HTTPS GET request to `/health` on the same configured endpoint to check server availability. This request contains no access token, chat question, or sensor values. The server, hosting provider, or network may nevertheless receive the IP address, request time, and request metadata; logging and retention depend on those providers and must be reviewed before public release.

4. Purposes and choices
Data is used to display/test device connection, evaluate prototype status, manage history and alerts, and answer chatbot questions when enabled. Location can be refused without disabling BLE. Cloud and AI processing requires a separate optional opt-in, not bundled with local-use acknowledgement; users can turn off remote-AI consent from the chat screen.

5. Security and retention
Local profile/health fields, location, and alert history use the platform secure-storage service (for example Keychain/Keystore, depending on platform) with account-scoped keys. The current app flow keeps continuous sensor readings in memory and does not persist them locally. Access, backup/deletion behavior, and provider retention still depend on platform and Supabase configuration; verify them on real devices before distribution.

6. Rights and contact
Contact the developer at norapolamarit@gmail.com with questions or data requests. If the deletion API is configured, the app can delete the authenticated account, associated Cloud API/Firestore event records, and that account's local profile/alert history. Data retained by external providers may require separate handling. The in-memory sensor buffer can be exported before deletion. The developer must define and test request-handling timelines before public release.

7. Children
There is no age-verification or guardian-consent workflow. Do not release for use by minors until the applicable requirements and safeguards are assessed and implemented.

8. Changes
Material changes should update the version and be communicated through a channel established by the developer.
