# Project State

## Current Position
**Phase:** 5 — End-to-End Verification & Real-World Hardening
**Status:** Ready to discuss / plan
**Last activity:** 2026-10-29 — Phase 4 executed and verified successfully

## Completed Phases
- **Phase 1: UVC Camera & Smart Glasses Stream Reliability** (Plans 01-01, 01-02 complete)
  - Unified `UvcCameraService` singleton
  - In-memory 2 fps frame stream buffer
  - Automated haptic + TTS disconnect alert & dual-camera failover/recovery
- **Phase 2: Real-Time Vision & Spatial Memory Integration** (Plans 02-01, 02-02 complete)
  - In-memory TFLite byte inference without disk I/O
  - Clock bearings (10 to 2 o'clock) & Option C combined spatial phrasing
  - Continuous 2 fps smart glasses feed into live obstacle monitoring
  - Instant dual-check item queries (live vision first, saved memory fallback)
  - 12-second audio fatigue cooldown with <1.2m forward hazard override
- **Phase 3: Camera Failover & Offline Resilience Pipeline** (Plans 03-01, 03-02 complete)
  - Fast-fail Gemini Live offline degradation in < 50ms without candidate model loops
  - Seamless offline voice intent fallback to VoiceCommandParser without API key errors
  - Multimodal RECALL_ITEM instant dual-check (live camera first, saved memory fallback)
  - Offline favorite places resolution and direct compass bearing fallback
  - Mid-inference USB disconnect capture protection against PlatformException
  - Automatic live obstacle loop resumption at 2 fps upon smart glasses reconnection
  - Leak-free phone CameraController disposal on hot-plug switch
- **Phase 4: Interactive Query & Low-Latency Audio Coordination** (Plans 04-01, 04-02 complete)
  - Zero-latency local fast-path for spatial and obstacle inquiries in < 350ms
  - Front-loaded concise spatial phrasing ("[Label]: [Clock], [Dist]")
  - Clock-based directional haptic pulses (left, center, right) and sonar click earcons
  - Immediate TTS preemption for Tier 0 (emergency) and Tier 1 (hazard) alerts
  - Microphone muting during hazard alerts with 300ms acoustic grace period to prevent echo feedback

## Key Decisions

| Decision | Phase | Source | Rationale |
|----------|-------|--------|-----------|
| UVC Smart Glasses as primary sensor | Init | User | Hands-free sight assistance for visually impaired users |
| YJX-C5 smart glasses @ 640x480 | Phase 1 | User | Low-latency ML inference and zero USB bus saturation |
| Unify UvcCameraService as single controller | Phase 1 | User | Eliminate duplicate UVCCameraControllers & native crashes |
| In-memory frame buffer (2 fps sampling) | Phase 1 | User | Eliminate flash disk I/O latency, jitter & GC churn |
| 100% automatic failover & recovery with TTS/haptics | Phase 1 | User | Essential for visually impaired users who cannot see screen dialogs |
| In-memory byte inference in ObjectDetectorService | Phase 2 | User / Architecture | Run live detection on smart glasses stream without file I/O |
| Instant dual-check item queries | Phase 2 | User | Live camera view check first, then fall back to saved memory |
| Combined relative + clock spatial directions | Phase 2 | User | Most intuitive bearing format for visually impaired orientation |
| Proximity-aware 12-second audio cooldown | Phase 2 | User | Prevent speech fatigue while bypassing for critical hazards (<1.2m) |
| Fast-fail offline degradation (< 50ms) | Phase 3 | User | Eliminate 32s model timeouts and erroneous API key speech when offline |
| Mid-inference USB disconnect hardening | Phase 3 | User | Protect captureFrame against native PlatformException and JNI crashes |
| Auto-restore live obstacle loop on re-plug | Phase 3 | User | Seamlessly resume 2 fps UVC stream monitoring without manual user action |
| Unified RECALL_ITEM dual-check | Phase 3 | User | Live visual scan first, then stored location in both online & offline flows |
| Zero-latency local fast-path for spatial queries | Phase 4 | User | Sub-350ms response for where/what visual queries via in-memory frames |
| Immediate audio preemption for hazards | Phase 4 | User | Tier 0/1 safety alerts preempt ambient speech and purge lower priority queues |
| Mic mute window with 300ms acoustic grace period | Phase 4 | User | Eliminate acoustic speaker-to-mic feedback loops during hazard warnings |
| Front-loaded spatial phrasing & directional haptics | Phase 4 | User | "[Item]: [Clock], [Dist]" format with left/center/right motor patterns |

### Blockers / Concerns
- Need to ensure Android `flutter_uvc_camera` permissions and USB device filters handle hot-plug without native crashes.
- Verification of physical UVC hardware events will require testing on target Android device / emulator with USB passthrough.

---
*Last updated: 2026-10-29*

