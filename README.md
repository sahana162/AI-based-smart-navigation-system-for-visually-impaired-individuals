# Smart Navigation (Alice)

**AI-Powered Voice-First Navigation & Vision Assistant for the Visually Impaired**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue.svg)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2.svg)](https://dart.dev)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Accessibility](https://img.shields.io/badge/Accessibility-WCAG%20AAA-gold.svg)](#accessibility-standards)

---

## Overview

**Smart Navigation** is an assistive mobile application designed to grant independent mobility and environmental awareness to visually impaired and blind individuals. Centered around **Alice**, an intelligent on-device voice companion, the application provides real-time collision warnings, pedestrian turn-by-turn guidance, sign/text reading, Indian Rupee currency recognition, personal item finding, and an instant Emergency SOS location broadcast.

The app is built from the ground up with **Voice-First** and **Accessibility-First** architecture:
* **Single-Speaker Discipline**: The assistant never speaks over the user and pauses microphone listening during Text-to-Speech (TTS) playback to eliminate acoustic feedback loops.
* **True Bilingual Support**: Seamless switching between English (`en-US`) and Kannada (`kn-IN`), including natural Subject-Object-Verb (SOV) grammar parsing.
* **Zero Cloud Latency for Critical Safety**: Obstacle alerts, text extraction, and object recognition run 100% on-device using Google ML Kit and TensorFlow Lite.

---

## Key Features

### 1. Live Camera Streaming & Obstacle Collision Alerts
* **Sub-60ms On-Device Processing**: Streams camera frames directly through in-memory byte buffers (`InputImage.fromBytes`) using Google ML Kit without writing temporary files to disk.
* **Multi-Level Haptic Collision Warnings**:
  * **Critical Proximity (< 1.5m, Ahead)**: High-frequency heavy haptic pulses (`HapticFeedback.heavyImpact()`) + urgent audio warnings.
  * **Approaching Obstacle**: Medium haptic alerts with directional callouts (*"Obstacle ahead"*, *"Chair to your right"*).
  * **Clear Path**: Low-frequency affirmative vibration when the forward pathway is clear.
* **Camera Mutex Protection**: Gracefully pauses live streaming when capturing high-resolution snapshots for OCR or currency checks, preventing platform `CameraException` race conditions.

### 2. Pedestrian Navigation with Clock-Face Bearing Guidance
* **OpenStreetMap (OSM) & OSRM Routing**: Generates true walking routes tailored for pedestrians, footpaths, and crossings.
* **Spatial Clock-Face Audio Guidance**: Translates compass bearings and device heading into natural clock positions:
  * *"In 30 meters, turn right onto Main Street at your 2 o'clock"*
  * *"30 ಮೀಟರ್‌ಗಳಲ್ಲಿ, Oak Street ಕಡೆಗೆ ಬಲಕ್ಕೆ ತಿರುಗಿ (2 ಗಂಟೆಯ ದಿಕ್ಕಿನಲ್ಲಿ)"*
* **Direct Compass Failover Guidance**: If the OSRM walking router is unreachable, offline, or rate-limited, the system seamlessly activates Direct Compass Guidance mode, providing continuous distance and 12-hour clock-face updates directly towards destination coordinates without leaving the pedestrian stranded.
* **Screen-Off Background Tracking**: Configured with iOS `UIBackgroundModes` (`location`, `audio`) and Android `FOREGROUND_SERVICE_LOCATION` + `ACCESS_BACKGROUND_LOCATION` + `WAKE_LOCK` to ensure turn-by-turn spoken guidance continues uninterrupted when the phone is locked inside a pocket or bag.
* **Offline Destination Memory Cache**: Persists previously queried landmarks and coordinates in `StorageService`, enabling instantaneous offline route calculation without network latency.
* **Cross-Track Polyline Deviation Detection**: Employs minimum distance-to-segment geometric calculations to detect genuine off-route deviation (> 50m) while preventing false recalculation loops on winding sidewalks.

### 3. Emergency SOS & Real-Time Location Broadcast
* **Automatic GPS Acquisition**: Instantly locks device satellite coordinates upon triggering Emergency Mode via voice command (*"Emergency"* / *"ತುರ್ತು ಸಹಾಯ"*) or tactile SOS buttons.
* **Reverse Geocoding**: Queries OpenStreetMap Nominatim with safe rate-limiting and user-agent attribution to announce nearest street names and landmarks aloud.
* **Spoken & Visual High-Contrast Broadcast**:
  * Voice: *"Emergency alert! Your GPS coordinates are latitude 12.9716, longitude 77.5946, near MG Road. Call 112 immediately."*
  * UI: Ultra-high contrast danger card showing live coordinates, accuracy radius (±4m), nearest address, and one-tap emergency calling.

### 4. Bilingual Vision Tools (English & Kannada)
* **Surroundings Description**: Identifies multiple objects in the camera frame with sector-based spatial positioning (*left*, *center*, *right*) and proximity depth, translated naturally into English (*"Ahead of you: person close by. To your left: chair"*) or Kannada (*"ಮುಂದೆ: ವ್ಯಕ್ತಿ ಸಮೀಪದಲ್ಲಿದೆ. ನಿಮ್ಮ ಎಡಕ್ಕೆ: ಕುರ್ಚಿ"*).
* **Live Obstacle Alerts**: Warns of impending obstacles with directional callouts in both languages (*"Caution! chair directly ahead"* / *"ಎಚ್ಚರಿಕೆ! ಕುರ್ಚಿ ನೇರವಾಗಿ ಮುಂದೆ, ಸಮೀಪದಲ್ಲಿದೆ"*).
* **Read Text (OCR)**: Reads visible signs, noticeboards, food packaging labels, and prescription documents aloud in natural reading order.
* **Currency Recognition**: Verifies genuine Indian Rupee banknotes (₹10, ₹20, ₹50, ₹100, ₹200, ₹500, ₹2000) using RBI security markers, preventing false positive readings on receipts and price tags (*"ಭಾರತೀಯ ಕರೆನ್ಸಿ ನೋಟು: 500 ರೂಪಾಯಿ"*).
* **Find Lost Items**: Locates personal belongings (keys, white cane, bag, water bottle) with synonym matching, possessive pronoun handling, and reverse Kannada-to-COCO mapping (*"Find my keys"* / *"ಕೀ ಹುಡುಕಿ"*, *"ಕುರ್ಚಿ ಹುಡುಕಿ"*).

### 6. "Around Me" Spatial Map Exploration
* **OpenStreetMap Overpass POI Scanner**: Discovers essential civic infrastructure within 150 meters (bus stops, pedestrian crossings, pharmacies, clinics, ATMs, banks, and grocery stores).
* **Clock-Face Bearing Audio Delivery**: Projects points of interest onto a 12-hour clock face (*"Found 3 places within 150 meters: Bus stop, 40 meters straight ahead. Apollo Pharmacy, 75 meters at your 2 o'clock"* / Kannada: *"75 ಮೀಟರ್ 2 ಗಂಟೆಯ ದಿಕ್ಕಿನಲ್ಲಿ ಅಪೊಲೊ ಫಾರ್ಮಸಿ"*).

### 7. Multi-Modal Indian Rupee Banknote Recognition
* **Color Tint & OCR Fusion**: Samples image center-grid pixels to calculate authentic RGB and HSV color profiles for Mahatma Gandhi New Series banknotes:
  * **₹500**: Stone Grey (low saturation, balanced luminance)
  * **₹200**: Bright Orange / Yellow-Orange (Hue 25°–55°)
  * **₹100**: Lavender / Violet (Hue 220°–285°)
  * **₹50**: Fluorescent Blue / Cyan (Hue 170°–220°)
  * **₹20**: Greenish Yellow (Hue 60°–95°)
  * **₹10**: Chocolate Brown (Hue 15°–40°, earthy tone)
  * **₹2000**: Magenta (Hue 290°–355°)
* **Folded/Creased Note Tolerance**: Even when banknotes are folded, held at an angle, or partially obscured so OCR text is missed, authentic color verification provides confidence confirmation.

### 8. Acoustic Proximity Sonar & Low-Light Auto-Torch
* **Acoustic Sonar Earcons**: When obstacles are detected in front of the pedestrian, emits rhythmic acoustic sound cues (`SystemSound.play(SystemSoundType.click)`) and tactile pulses that accelerate as distance shrinks. This maintains obstacle awareness without speech chatter drowning out traffic and cane taps.
* **Low-Light Environment Detection**: Continuously checks camera frame luminance; if the user enters a pitch-black corridor or unlit street, automatically turns on the camera flashlight with spoken feedback (*"Lighting is dark. Flashlight turned on"*).
* **Full-Screen Screen-Reader Gestures**:
  * **Single Tap**: Speaks current turn-by-turn guidance or obstacle status aloud.
  * **Double Tap**: Activates or pauses speech recognition.
  * **Horizontal Swipe (Left / Right)**: Immediately toggles camera flashlight on or off.

### 9. City Transit & Bus Route Reader
* **Windshield Display OCR**: Specifically optimized for city bus route numbers (e.g., `500-D`, `335-E`, `201-G`, `KBS-1`, `V-335E`, `415H`) and destination boards (`Majestic`, `Whitefield`, `Electronic City`, `Silk Board`, `ಮೆಜೆಸ್ಟಿಕ್`).
* Spoken output: *"Approaching bus: Route 500-D towards Central Silk Board"* / *"ಬಸ್ 500-D ಬರುತ್ತಿದೆ"*.

### 10. Compass Orientation & Interactive Capabilities Guide
* **Facing Direction Query**: Announces device compass heading and 8-point cardinal orientation (*"You are facing North-East, 48 degrees"* / *"ನೀವು ಈಶಾನ್ಯ (48 ಡಿಗ್ರಿ) ದಿಕ್ಕಿಗೆ ಮುಖ ಮಾಡಿದ್ದೀರಿ"*).
* **Interactive Capabilities Guide**: Tap the guide button on the home screen or long-press any tactile tool chip to access spoken descriptions and launch straight into camera or guidance mode via the **"Try This Feature Now"** button.

### 11. On-Device Traffic Light & Pedestrian Crossing Assistant
* **Real-Time Signal State Analysis**: Detects traffic signal housings and performs on-device vertical chroma dominance analysis to determine Red, Green, or Amber states without cloud latency:
  * **Red Light**: Urgent warning (*"Red light detected. Do not cross"* / *"ಕೆಂಪು ದೀಪ! ರಸ್ತೆ ದಾಟಬೇಡಿ"*).
  * **Green Light**: Affirmative crossing advisory (*"Green light detected. Safe to cross"* / *"ಹಸಿರು ದೀಪ! ಎಚ್ಚರಿಕೆಯಿಂದ ರಸ್ತೆ ದಾಟಬಹುದು"*).
  * **Amber / Uncertain**: Defensive safety advisory (*"Signal is changing or uncertain. Wait and listen for vehicle engine noise before proceeding"*).
* **Stop Sign Detection**: Flags active stop sign markers in pedestrian pathways.

### 12. Instant Favorite Places (Home & Work) & Directional Turn Haptics
* **One-Step Voice GPS Bookmarking**: Say *"Save as home"* or *"Save as work"* (*"ಮನೆಯಾಗಿ ಉಳಿಸು"*) during navigation to store exact GPS coordinates and street addresses in encrypted local storage.
* **Instant Routing**: Say *"Take me home"* or *"Take me to work"* (*"ಮನೆಗೆ ಕರೆದೊಯ್ಯಿರಿ"*) for instant walking route calculation without re-entering addresses or relying on search connectivity.
* **Directional Spatial Turn Haptics**: Overcomes loud city traffic and earbud acoustic masking using distinctive tactile rhythms:
  * **Turn Left**: 2 distinct medium-heavy pulses (`··`).
  * **Turn Right**: 3 distinct medium-heavy pulses (`···`).
  * **Arrival**: Double heavy impact pulse (`▬▬`).
* **Pedestrian Step Count Guidance**: Translates meter distances into physical cane-walking steps (e.g., *"In 15 meters, approx 20 steps, turn left onto MG Road"*).

---

## Accessibility Standards (WCAG AAA)

* **Contrast Ratios**: Exceeds WCAG AAA requirements (7:1 contrast ratio) using a pure high-contrast palette:
  * Background: Pure Black (`#000000`)
  * Primary Accent: Warning Amber / Gold (`#FFD700`)
  * Secondary Accent: Cyan Glow (`#00FFFF`)
  * Accent Highlight: High-Visibility Yellow (`#FFFF00` / `#FFEB3B`)
  * Danger / Emergency: High-Visibility Crimson (`#FF3B30`)
* **iOS Silent Switch Bypass**: Configures `AVAudioSessionCategoryPlayback` with `duckOthers` to ensure critical guidance audio plays when the hardware mute switch is engaged.
* **Touch Target Sizing**: All interactive touch surfaces exceed the minimum 48x48dp requirement (primary navigation buttons are 56dp+).
* **Screen Reader Integration**: Every widget includes descriptive `Semantics` tags, custom actions, live regions for status announcements, and double-tap hints for TalkBack (Android) and VoiceOver (iOS).
* **Dynamic Type Support**: Layouts are wrapped in overflow-safe scroll containers to gracefully handle up to 2.0x system font scaling without `RenderFlex` overflow errors.

---

## Voice Commands Reference

Alice can be activated hands-free using the wake word **"Alice"** (or **"ಆಲಿಸ್"** in Kannada), or by double-tapping anywhere on the screen:

| Action | English Voice Command | Kannada Voice Command (SOV Supported) |
| :--- | :--- | :--- |
| **Start Navigation** | *"Start navigation"*, *"Open camera"* | *"ನ್ಯಾವಿಗೇಷನ್ ಪ್ರಾರಂಭಿಸಿ"*, *"ಕ್ಯಾಮೆರಾ ತೆರೆಯಿರಿ"* |
| **Navigate to Place** | *"Take me to [Destination]"* | *"[ಸ್ಥಳ] ಕ್ಕೆ ದಾರಿ ತೋರಿಸಿ"*, *"[ಸ್ಥಳ] ಕ್ಕೆ ಕರೆದೊಯ್ಯಿರಿ"* |
| **Navigate to Home/Work** | *"Take me home"*, *"Navigate to work"* | *"ಮನೆಗೆ ದಾರಿ ತೋರಿಸಿ"*, *"ಕಚೇರಿಗೆ ಕರೆದೊಯ್ಯಿರಿ"* |
| **Save Bookmark** | *"Save as home"*, *"Save current location as work"* | *"ಮನೆಯಾಗಿ ಉಳಿಸು"*, *"ಕಚೇರಿಯಾಗಿ ಉಳಿಸು"* |
| **Check Traffic Signal** | *"Check traffic light"*, *"Is it safe to cross?"* | *"ಟ್ರ್ಯಾಫಿಕ್ ಲೈಟ್ ಚೆಕ್ ಮಾಡು"*, *"ರಸ್ತೆ ದಾಟಲು ಸುರಕ್ಷಿತವೇ?"* |
| **Where Am I?** | *"Where am I?"*, *"What is my location?"* | *"ನಾನು ಎಲ್ಲಿದ್ದೇನೆ?"*, *"ನನ್ನ ಪ್ರಸ್ತುತ ಸ್ಥಳ ಯಾವುದು?"* |
| **Around Me (Explore)** | *"Around me"*, *"What is around me?"* | *"ಏನಿದೆ ಸುತ್ತಮುತ್ತ?"*, *"ಸುತ್ತಲಿನ ಸ್ಥಳಗಳು"*, *"ಸುತ್ತಲೂ ಏನಿದೆ"* |
| **Facing Direction** | *"Which way am I facing?"*, *"Compass heading"* | *"ಯಾವ ದಿಕ್ಕಿಗೆ ಮುಖ ಮಾಡಿದ್ದೇನೆ?"*, *"ದಿಕ್ಕು ಯಾವುದು?"* |
| **Obstacle Alerts** | *"Toggle obstacle alerts"*, *"Pause alerts"* | *"ಅಡೆತಡೆ ಎಚ್ಚರಿಕೆ"*, *"ಎಚ್ಚರಿಕೆ ನಿಲ್ಲಿಸಿ"* |
| **Camera Flashlight** | *"Turn on torch"*, *"Turn off flashlight"* | *"ಟಾರ್ಚ್ ಆನ್ ಮಾಡಿ"*, *"ಟಾರ್ಚ್ ಆಫ್ ಮಾಡಿ"* |
| **Describe View** | *"Describe surroundings"*, *"What's in front of me?"* | *"ಸುತ್ತಮುತ್ತಲಿನ ವಿವರಣೆ"*, *"ಮುಂದೆ ಏನಿದೆ?"* |
| **Read Text (OCR)** | *"Read text"*, *"Read this sign"* | *"ಪಠ್ಯ ಓದಿ"*, *"ಬೋರ್ಡ್ ಓದಿ"* |
| **Read Bus Number** | *"What bus is this?"*, *"Read bus route"*, *"Read bus board"* | *"ಯಾವ ಬಸ್ ಬರುತ್ತಿದೆ?"*, *"ಬಸ್ ಸಂಖ್ಯೆ ಓದಿ"*, *"ಬಸ್ ಬೋರ್ಡ್ ಓದಿ"* |
| **Currency Detection** | *"Recognize currency"*, *"How much money is this?"* | *"ಕರೆನ್ಸಿ ಗುರುತಿಸಿ"*, *"ನೋಟು ಎಷ್ಟು?"* |
| **Find Item** | *"Find my [item]"*, *"Where are my keys?"* | *"[ವಸ್ತು] ಹುಡುಕಿ"*, *"ಕೀ ಹುಡುಕಿ"* |
| **Save Item** | *"Save item [name]"*, *"Remember this item"* | *"[ವಸ್ತು] ನೆನಪಿಡಿ"*, *"ವಾಕಿಂಗ್ ಸ್ಟಿಕ್ ಉಳಿಸಿ"* |
| **Battery & Device Status** | *"Battery status"*, *"Device status"* | *"ಬ್ಯಾಟರಿ ಸ್ಥಿತಿ"*, *"ಫೋನ್ ಸ್ಥಿತಿ"* |
| **Repeat Speech** | *"Repeat"*, *"Say that again"* | *"ಪುನರಾವರ್ತಿಸಿ"*, *"ಮತ್ತೆ ಹೇಳಿ"* |
| **Stop Audio** | *"Be quiet"*, *"Stop speaking"* | *"ಶಾಂತರಾಗಿ"*, *"ಮಾತು ನಿಲ್ಲಿಸಿ"* |
| **Language Switch** | *"Switch to Kannada"*, *"Switch to English"* | *"ಕನ್ನಡಕ್ಕೆ ಬದಲಾಯಿಸಿ"*, *"ಇಂಗ್ಲಿಷ್‌ಗೆ ಬದಲಾಯಿಸಿ"* |
| **Emergency SOS** | *"Emergency"*, *"Help me emergency"* | *"ತುರ್ತು ಸಹಾಯ"*, *"ತುರ್ತು ಪರಿಸ್ಥಿತಿ"* |

---

## Architecture & Code Structure

```
lib/
├── core/
│   ├── localization/
│   │   └── app_strings.dart             # Localized English & Kannada string catalogs
│   ├── services/
│   │   ├── object_detector_service.dart # On-device MobileNet SSD TFLite detector
│   │   ├── pedestrian_navigation_service.dart # OSM/OSRM pedestrian turn-by-turn routing
│   │   ├── speech_service.dart          # Speech-to-Text wrapper with error categorization
│   │   ├── storage_service.dart         # SharedPreferences settings & registered items
│   │   ├── tts_service.dart             # Text-to-Speech service with acoustic loop guard
│   │   ├── vision_service.dart          # ML Kit vision pipeline (OCR, object, currency)
│   │   ├── voice_command_parser.dart    # Natural language parser with Kannada SOV grammar
│   │   └── voice_session_coordinator.dart # Central state machine coordinating voice lifecycle
│   └── theme/
│       └── app_theme.dart               # High-contrast WCAG AAA color palette & styles
├── models/
│   ├── navigation_step.dart             # Pedestrian step, bearing, and clock-face directions
│   └── voice_command.dart               # Voice command enum & argument models
├── ui/
│   ├── screens/
│   │   ├── feature_detail_screen.dart   # Detail views & Live Emergency SOS screen
│   │   ├── home_screen.dart             # Clean voice-first companion home interface
│   │   ├── navigation_screen.dart       # Real-time camera feed & live obstacle overlay
│   │   └── settings_screen.dart         # Assistant name, speed, pitch, language & SOS contact
│   └── widgets/
│       └── accessible_button.dart       # High-contrast tactile buttons with semantic hints
└── main.dart                            # App initialization, service wiring & routing
```

---

## Getting Started

### Prerequisites
* **Flutter SDK**: `>=3.3.0 <4.0.0`
* **Dart SDK**: `>=3.0.0`
* **Android**: Minimum SDK `21`, Target SDK `34`
* **iOS**: iOS `12.0` or higher

### Installation

1. **Clone the repository**:
   ```bash
   git clone https://github.com/your-username/blind_navigation.git
   cd blind_navigation
   ```

2. **Install dependencies**:
   ```bash
   flutter pub get
   ```

3. **Verify model assets**:
   Ensure `assets/models/ssd_mobilenet/detect.tflite` and `labelmap.txt` are present in `assets/models/`.

4. **Run on connected device**:
   ```bash
   flutter run
   ```

### Platform Permissions Configured

* **iOS** (`ios/Runner/Info.plist`):
  * `NSCameraUsageDescription`: Camera access for obstacle detection, sign reading, and currency recognition.
  * `NSMicrophoneUsageDescription`: Microphone access for spoken voice commands.
  * `NSSpeechRecognitionUsageDescription`: Speech recognition for hands-free assistant control.
  * `NSLocationWhenInUseUsageDescription`: GPS access for pedestrian turn-by-turn guidance and Emergency SOS.
* **Android** (`android/app/src/main/AndroidManifest.xml`):
  * `android.permission.CAMERA`
  * `android.permission.RECORD_AUDIO`
  * `android.permission.ACCESS_FINE_LOCATION`
  * `android.permission.ACCESS_COARSE_LOCATION`
  * `android.permission.INTERNET`

---

## Running Automated Tests

The repository includes comprehensive unit and widget tests covering all services, voice command parsing, Kannada SOV grammar, and screen accessibility:

```bash
flutter test
```

Test suites verify:
* Voice command parser across natural English and Kannada phrasing.
* Spatial clock-face pedestrian instruction generation.
* Emergency SOS GPS acquisition and reverse geocoding.
* Settings screen persistence and emergency contact configuration.
* Screen reader semantics and high-contrast rendering across all screens.

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
