#!/usr/bin/env bash
# Build doz app สำหรับแจกจ่าย (ฝัง URL ของ cloud server ตอน build)
# วิธีใช้:  ./build_apps.sh https://your-service.onrender.com
set -e

CLOUD_URL="${1:-}"
if [ -z "$CLOUD_URL" ]; then
  echo "❌ ใส่ URL ของ cloud server ด้วย"
  echo "   ตัวอย่าง: ./build_apps.sh https://vita-gaurd-cloud-api.onrender.com"
  exit 1
fi

echo "🌐 Cloud URL: $CLOUD_URL"
echo "📦 flutter pub get ..."
flutter pub get

echo ""
echo "🤖 Building Android APK (release) ..."
flutter build apk --release \
  --dart-define=VITAGAURD_CLOUD_BASE_URL="$CLOUD_URL"
echo "✅ APK: build/app/outputs/flutter-apk/app-release.apk"

# (ทางเลือก) Android App Bundle สำหรับ Google Play
# flutter build appbundle --release --dart-define=VITAGAURD_CLOUD_BASE_URL="$CLOUD_URL"

echo ""
echo "🍎 Building iOS (release, no codesign) ..."
echo "   * ต้องเปิด Xcode เซ็น signing + archive เพื่ออัป TestFlight อีกที"
flutter build ios --release --no-codesign \
  --dart-define=VITAGAURD_CLOUD_BASE_URL="$CLOUD_URL" || \
  echo "⚠️  iOS build ข้าม (ต้องรันบน macOS + มี Xcode)"

echo ""
echo "🎉 เสร็จ — APK พร้อมแจก / iOS ไปต่อใน Xcode (Product > Archive)"
