#!/usr/bin/env bash
# EN: Stop on command failures, unset variables, and broken pipelines. TH: หยุดเมื่อคำสั่งผิด ตัวแปรไม่ครบ หรือ pipeline ล้มเหลว
set -euo pipefail

# EN: Require the public Supabase project URL for release Auth. TH: บังคับมี URL Supabase สาธารณะสำหรับ Auth ของ release
: "${DOZ_SUPABASE_URL:?Set DOZ_SUPABASE_URL in Render static-site environment}"
# EN: Require the browser-safe public key for release Auth. TH: บังคับมี public key ที่ใช้ใน browser ได้
: "${DOZ_SUPABASE_PUBLISHABLE_KEY:?Set DOZ_SUPABASE_PUBLISHABLE_KEY in Render static-site environment}"

# EN: Use the verified Cloud API host until a new one is explicitly configured. TH: ใช้ Cloud API ที่ตรวจแล้วหากไม่ได้กำหนดค่าใหม่
DOZ_WEB_API_URL="${VITAGAURD_CLOUD_BASE_URL:-https://drive-alert.onrender.com}"
# EN: Refuse non-HTTPS remote APIs in the release web build. TH: ปฏิเสธ API ที่ไม่ใช่ HTTPS สำหรับเว็บ release
case "$DOZ_WEB_API_URL" in
  https://*) ;;
  *) echo 'Cloud API URL must start with https://' >&2; exit 1 ;;
esac

# EN: Install a fixed Flutter SDK version when Render does not provide one. TH: ติดตั้ง Flutter เวอร์ชันคงที่เมื่อ Render ไม่มีให้
if ! command -v flutter >/dev/null 2>&1; then
  # EN: Place the SDK outside the repository and generated web assets. TH: วาง SDK นอก repository และไฟล์เว็บที่เผยแพร่
  FLUTTER_SDK_DIR="${TMPDIR:-/tmp}/doz-flutter-sdk"
  # EN: Fetch the same SDK version used for the local verified build. TH: ดึง SDK เวอร์ชันเดียวกับที่ build ในเครื่องผ่าน
  git clone --depth 1 --branch 3.44.1 https://github.com/flutter/flutter.git "$FLUTTER_SDK_DIR"
  # EN: Make that SDK available only to this build process. TH: เพิ่ม SDK ลง PATH เฉพาะขั้นตอน build นี้
  export PATH="$FLUTTER_SDK_DIR/bin:$PATH"
fi

# EN: Show the compiler version without printing any configuration value. TH: แสดงเวอร์ชันตัว build โดยไม่เผยค่า config
flutter --version
# EN: Reject malformed public Auth/API settings before compiling web assets. TH: ปฏิเสธค่า Auth/API สาธารณะที่ผิดก่อน build ไฟล์เว็บ
dart scripts/validate_web_config.dart
# EN: Resolve dependencies from the pinned lockfile. TH: ติดตั้ง dependency ตาม lockfile ที่บันทึกไว้
flutter pub get
# EN: Compile a release web build with only public client settings. TH: build เว็บ release ด้วย config สาธารณะเท่านั้น
flutter build web --release --no-pub \
  "--dart-define=DOZ_SUPABASE_URL=$DOZ_SUPABASE_URL" \
  "--dart-define=DOZ_SUPABASE_PUBLISHABLE_KEY=$DOZ_SUPABASE_PUBLISHABLE_KEY" \
  "--dart-define=VITAGAURD_CLOUD_BASE_URL=$DOZ_WEB_API_URL"
# EN: Fail if the expected static entry point was not generated. TH: หยุดหากไม่พบไฟล์เริ่มต้นของเว็บ
test -s build/web/index.html
