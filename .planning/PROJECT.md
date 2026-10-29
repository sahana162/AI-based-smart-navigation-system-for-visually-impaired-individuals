# AI-Based Smart Navigation Assistant

## Vision
An AI-powered assistive navigation and situational awareness system designed for visually impaired and blind users. Paired with wearable smart glasses (via external USB UVC camera) and mobile sensors, the assistant provides real-time, low-latency auditory guidance, hazard avoidance, environmental reading, and conversational spatial memory.

## Core Value
Reliable, hands-free spatial sight assistance that seamlessly interprets the user's visual surroundings through wearable smart glasses, retains item and environment memory, and communicates immediate, life-critical feedback without lag or unhandled disconnects.

## Target Users
- Visually impaired, low-vision, and blind individuals navigating urban pedestrian environments and indoor spaces.
- Users requiring intuitive, voice-first interaction and smart wearable camera feeds rather than holding up a mobile phone continuously.

## Technical Context
- **Platform:** Flutter (Android-first for USB Host / OTG UVC camera peripheral access).
- **Camera Pipeline:** Dual camera architecture:
  - Primary: Wearable smart glasses via USB UVC camera (`flutter_uvc_camera`, OV5648).
  - Fallback: Device internal camera (`camera` package).
- **Vision Pipeline:**
  - On-Device: TFLite SSD MobileNet v1/v2 (`tflite_flutter`), Google ML Kit Object Detection & Text Recognition (`google_mlkit_object_detection`, `google_mlkit_text_recognition`).
  - Multimodal AI: Google Gemini Live API (`gemini_live_service`) with fallback REST models (`gemini-3.5-flash-lite`).
- **Voice & Audio Pipeline:**
  - Input: Android Speech-to-Text (`speech_to_text`).
  - Output: Text-to-Speech (`flutter_tts`) with acoustic feedback cancellation and tone cues.
  - Coordination: `VoiceSessionCoordinator` managing turn-taking, wake words, and screen delegates.
- **Navigation:** Pedestrian routing & geo-tracking (`geolocator`, `pedestrian_navigation_service`).
- **Storage:** Local persistent preferences and remembered item memory (`shared_preferences`, `storage_service`).

## Requirements

### Active
- [ ] Solidify UVC camera / smart glasses handshake, USB permission prompt, reconnection on plug/unplug, and stream stability.
- [ ] Connect real-time visual scene analysis to voice session memory (match detected objects against `RememberedItem` profiles and announce spatial coordinates).
- [ ] Establish sub-second audio announcements for immediate hazards and requested objects while suppressing redundant repetitive chatter.
- [ ] Implement seamless automatic failover between UVC smart glasses and internal phone camera upon hardware disconnect/reconnect.
- [ ] Guarantee full on-device offline functionality for core navigation, object detection, and remembered item queries when internet/Gemini is unavailable.

### Out of Scope (Current Milestone)
- Custom BLE hardware firmware flashing (relies on standard UVC / USB Video Class protocol).
- iOS external UVC video streaming (iOS does not support generic OTG USB UVC controllers like Android).
- Cloud server account synchronization (all spatial memory stored securely on-device).

## Key Decisions

| Decision | Source | Rationale | Outcome |
|----------|--------|-----------|---------|
| Prioritize USB UVC Smart Glasses as default eye | User | Smart glasses provide true hands-free orientation for blind users | Active |
| Dual-camera fallback (UVC -> Mobile back camera) | User / Architecture | Hardware disconnects or loose cables must not blind the user | Active |
| Local ML first (TFLite/MLKit) with Gemini Live enhancement | User / Architecture | Immediate latency (<300ms) for hazards; cloud for conversational nuance | Active |
| Integrated Voice Session Coordinator | Codebase | Single lifecycle prevents audio echo and duplicate parsing | Preserved & Extended |

---
*Last updated: 2026-10-29 after initialization*

