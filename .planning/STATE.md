# Project State

## Current Position
**Phase:** 2 — Real-Time Vision & Spatial Memory Integration
**Status:** Plans created (02-01, 02-02), ready to execute
**Last activity:** 2026-10-29 — Phase 2 discussed and planned

## Completed Phases
- **Phase 1: UVC Camera & Smart Glasses Stream Reliability** (Plans 01-01, 01-02 complete)
  - Unified `UvcCameraService` singleton
  - In-memory 2 fps frame stream buffer
  - Automated haptic + TTS disconnect alert & dual-camera failover/recovery

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

### Blockers / Concerns
- Need to ensure Android `flutter_uvc_camera` permissions and USB device filters handle hot-plug without native crashes.
- Verification of physical UVC hardware events will require testing on target Android device / emulator with USB passthrough.

---
*Last updated: 2026-10-29*

