# Project State

## Current Position
**Phase:** 1 — UVC Camera & Smart Glasses Stream Reliability
**Status:** Ready to plan
**Last activity:** 2026-10-29 — Project initialized with GSD workflow

## Key Decisions

| Decision | Phase | Source | Rationale |
|----------|-------|--------|-----------|
| UVC Smart Glasses as primary sensor | Init | User | Hands-free sight assistance for visually impaired users |
| Instant phone camera fallback | Init | User / Architecture | Redundant visual safety net when USB cable drops or disconnects |
| On-device TFLite/MLKit for instant safety alerts | Init | User / Architecture | Cloud latency is too slow for immediate hazard notification |
| Spatial memory linkage with live detection | Init | User | Connecting `RememberedItem` with vision model outputs |

### Blockers / Concerns
- Need to ensure Android `flutter_uvc_camera` permissions and USB device filters handle hot-plug without native crashes.
- Verification of physical UVC hardware events will require testing on target Android device / emulator with USB passthrough.

---
*Last updated: 2026-10-29*

