# Dzoz Flutter Mobile App

Dzoz is a Flutter mobile prototype for Health Monitoring, Risk Detection, and Early Warning from an ESP32-based smartwatch. This version moves the core Streamlit logic into Dart so it can run like a mobile app.

## What Is Included

- Login / setup screen before entering the app, with Find device and Connect device steps
- Personal information: weight, height, age, gender, underlying disease / medical conditions
- Dark mobile dashboard
- Streamlit-like Flutter UI with a left Settings sidebar on wide screens and top tab buttons
- Current Health Status card
- Sensor cards for Heart Rate, SpO2, GSR, Stress Level, Temperature, battery, BLE status, and device connection
- Mock health stream when BLE is not connected
- BLE scan/connect service using `flutter_blue_plus`
- Local rule-based Risk Detection
- Health Data charts using `fl_chart`
- Risk Alert Log with user response buttons
- Health History comparison page
- Chatbot page with API call and local fallback
- Local alert history using `shared_preferences`

## Run

If platform folders are missing, generate them first:

```bash
flutter create .
flutter pub get
flutter run
```

## Connect To Cloud

The Flutter app can sync sensor data and alerts to a cloud HTTP API. Cloud settings are configured by the developer when running or building the app, so other users do not see cloud controls in the Settings screen.

Run with a local cloud URL:

```bash
flutter run --dart-define=VITAGAURD_CLOUD_BASE_URL=http://YOUR_COMPUTER_IP:8000
```

Build an app with a deployed cloud URL:

```bash
flutter build apk --release --dart-define=VITAGAURD_CLOUD_BASE_URL=https://YOUR_RENDER_SERVICE.onrender.com
```

The app sends:

- `POST /sensor` for sensor + current Risk Detection result
- `POST /alert` for alert events

The app still works locally if no cloud URL is provided or the cloud endpoint is offline.

## View Data From Other Devices On This Computer Only

Run the cloud API on this computer:

```bash
cd cloud_api
python3 -m pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000
```

Find this computer's local IP address, then set each phone app:

```bash
flutter run --dart-define=VITAGAURD_CLOUD_BASE_URL=http://YOUR_COMPUTER_IP:8000
```

Open this dashboard on the computer:

```text
http://localhost:8000/local-dashboard
```

The local dashboard is intentionally blocked from other devices. Other phones/devices can send data to this computer, but they cannot open the dashboard page.

For device apps, use this computer's LAN IP as the cloud URL:

```text
http://YOUR_COMPUTER_IP:8000
```

Each phone sends a persistent `deviceId`, user profile, sensor values, Risk Detection result, and alerts. The dashboard shows the latest data from every connected phone/device.

## Deploy Example Cloud API On Render

This repo includes an example cloud backend in:

```text
cloud_api/
```

Deploy steps:

1. Push `cloud_api/` to GitHub, or make it the root of a Render service.
2. On Render choose `New +` -> `Blueprint`.
3. Use `cloud_api/render.yaml`.
4. Render will run:

```text
Build Command:
python -m pip install -r requirements.txt

Start Command:
uvicorn main:app --host 0.0.0.0 --port $PORT
```

After deploy, test:

```text
https://YOUR_RENDER_SERVICE.onrender.com/health
```

Use that base URL when running or building the Flutter app:

```bash
flutter build apk --release --dart-define=VITAGAURD_CLOUD_BASE_URL=https://YOUR_RENDER_SERVICE.onrender.com
```

## User Settings

The in-app Settings area is intentionally limited for normal devices:

- Language
- Weight
- Height
- Age
- Gender
- Underlying disease / medical conditions
- Logout

Device connection, cloud URL, and API configuration are kept in setup/build configuration instead of the normal user Settings screen.

## BLE Device Connection

BLE is enabled with `flutter_blue_plus`.

Android permissions are configured in:

```text
android/app/src/main/AndroidManifest.xml
```

iOS Bluetooth usage descriptions are configured in:

```text
ios/Runner/Info.plist
```

On Android 12+, the app requests Bluetooth scan/connect permissions before scanning.

The ESP32 device should advertise with a name containing `ESP32`, or update `lib/services/ble_service.dart` to match your exact device name/service UUID/characteristic UUID.

## Build APK

```bash
flutter pub get
flutter build apk --release
```

The APK will be created under:

```text
build/app/outputs/flutter-apk/app-release.apk
```

If Android build fails, run:

```bash
flutter doctor -v
flutter doctor --android-licenses
```

Also install Android Studio Command-line Tools:

```text
Android Studio -> Settings -> Languages & Frameworks -> Android SDK -> SDK Tools -> Android SDK Command-line Tools
```

Then retry:

```bash
flutter build apk --release
```

## Chatbot API

The chatbot UI is currently hidden from the app. The Dart service code is still kept in the project so the feature can be enabled again later without rebuilding the core logic.

or an Ollama-style:

```json
{
  "response": "..."
}
```

If the API is unavailable, the app uses a local rule-based fallback.

The included `cloud_api` backend also has a basic `/chat` endpoint, so you can use:

```text
https://YOUR_RENDER_SERVICE.onrender.com/chat
```

## BLE Sensor JSON

The ESP32 notification payload should be JSON:

```json
{
  "heartRate": 78,
  "spo2": 97,
  "gsr": 45,
  "temperature": 36.7,
  "accelX": 0.1,
  "accelY": 0.2,
  "accelZ": 1.0,
  "gyroX": 0.02,
  "gyroY": 0.01,
  "gyroZ": 0.03
}
```

For a real prototype, update `lib/services/ble_service.dart` with your exact service UUID and characteristic UUID.

## Note

This project is a prototype for Health Monitoring, Risk Detection, Early Warning, safety recommendations, and user guidance.
