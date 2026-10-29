# Project State

## Current Position
**Phase:** 1 — UVC Camera & Smart Glasses Stream Reliability
**Status:** Plans created (01-01, 01-02), ready to execute
**Last activity:** 2026-10-29 — Phase 1 discussed and planned

## Key Decisions

| Decision | Phase | Source | Rationale |
|----------|-------|--------|-----------|
| UVC Smart Glasses as primary sensor | Init | User | Hands-free sight assistance for visually impaired users |
| YJX-C5 smart glasses @ 640x480 | Phase 1 | User | Low-latency ML inference and zero USB bus saturation |
| Unify UvcCameraService as single controller | Phase 1 | User | Eliminate duplicate UVCCameraControllers & native crashes |
| In-memory frame buffer (2 fps sampling) | Phase 1 | User | Eliminate flash disk I/O latency, jitter & GC churn |
| 100% automatic failover & recovery with TTS/haptics | Phase 1 | User | Essential for visually impaired users who cannot see screen dialogs |

### Blockers / Concerns
- Need to ensure Android `flutter_uvc_camera` permissions and USB device filters handle hot-plug without native crashes.
- Verification of physical UVC hardware events will require testing on target Android device / emulator with USB passthrough.

---
*Last updated: 2026-10-29*

