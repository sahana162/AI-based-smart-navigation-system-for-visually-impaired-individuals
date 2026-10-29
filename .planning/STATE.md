# Project State

## Current Position
**Phase:** 3 — Camera Failover & Offline Resilience Pipeline
**Status:** Planned (Plans 03-01, 03-02 ready for execution)
**Last activity:** 2026-10-29 — Phase 3 planned and context locked

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

### Blockers / Concerns
- Need to ensure Android `flutter_uvc_camera` permissions and USB device filters handle hot-plug without native crashes.
- Verification of physical UVC hardware events will require testing on target Android device / emulator with USB passthrough.

---
*Last updated: 2026-10-29*

