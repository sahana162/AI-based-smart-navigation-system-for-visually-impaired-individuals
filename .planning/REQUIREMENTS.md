# Requirements: AI-Based Smart Navigation Assistant

## Overview
Functional, performance, and reliability requirements for stabilizing the wearable smart glasses vision feed, bridging spatial object detection with conversational memory, and establishing ironclad offline and hardware fallback pipelines.

## V1 — Must Have (Primary Milestone)

### 1. UVC Camera & Smart Glasses Stream Reliability
| ID | Requirement | Phase | Status |
|----|-------------|-------|--------|
| R1.1 | **Handshake & Device Discovery**: Robust Android USB permission negotiation with explicit vendor/product filter fallback so glasses are recognized immediately on connect. | Phase 1 | Complete |
| R1.2 | **Lifecycle Hot-Plug / Unplug Detection**: Handle physical USB cord disconnects, reconnects, app pause/resume without application crashes or frozen frames. | Phase 1 | Complete |
| R1.3 | **Streaming Frame Pipeline**: Reliable frame extraction at fixed throttle (1-3 fps for continuous analysis, instant for query) without native memory leaks in `flutter_uvc_camera`. | Phase 1 | Complete |
| R1.4 | **Thermal & Power Throttling**: Adaptive frame processing intervals when idling or when device temperature elevates. | Phase 1 | Complete |

### 2. Real-Time Vision & Spatial Memory Integration
| ID | Requirement | Phase | Status |
|----|-------------|-------|--------|
| R2.1 | **Remembered Item Visual Matching**: Match live object detections (bounding boxes, class labels, spatial positions like left/center/right/distance) against stored `RememberedItem` profiles. | Phase 2 | Complete |
| R2.2 | **Contextual Scene Integration**: When user asks "Where did I put my keys/glasses/bag?", cross-reference the camera stream and remembered item log to announce real-time location. | Phase 2 | Complete |
| R2.3 | **Low-Latency Audio Announcement**: Audio feedback delivered under 500ms via TTS with directional cues ("Keys spotted 2 steps ahead, slightly to your left"). | Phase 4 | Complete |
| R2.4 | **Audio De-duplication & Suppression**: Prevent repetitive spamming of the same detected object/obstacle within a configurable cooldown window (e.g. 8-15 seconds). | Phase 2 | Complete |

### 3. Hardware Disconnect & Network Fallback Resilience
| ID | Requirement | Phase | Status |
|----|-------------|-------|--------|
| R3.1 | **Instant Camera Failover**: If the UVC glasses stream drops or is unplugged during active navigation, immediately fail over to the internal smartphone back camera with an accessible audio cue ("Glasses disconnected. Switching to phone camera."). | Phase 3 | Complete |
| R3.2 | **Seamless Re-attachment**: If smart glasses are plugged back in, automatically re-initialize UVC stream and switch back without requiring app restart. | Phase 3 | Complete |
| R3.3 | **Complete On-Device Offline Operation**: When offline (airplane mode or zero data), all hazard detection, TFLite object recognition, smart OCR, and remembered item recall must function locally without network calls or throwing unhandled HTTP errors. | Phase 3 | Complete |
| R3.4 | **Gemini Live / Cloud Degradation**: Graceful transition between multimodal Gemini Live cloud service and local heuristics/TFLite when network quality fluctuates. | Phase 3 | Complete |

## V2 — Nice to Have (Future Iterations)
| ID | Requirement | Priority | Status |
|----|-------------|----------|--------|
| R4.1 | Custom facial embedding matching for friends/family with glasses | Medium | Backlog |
| R4.2 | Fine-grained indoor spatial beacon integration | Low | Backlog |
| R4.3 | BLE battery & telemetry monitoring for powered smart glasses frames | Medium | Backlog |

## Out of Scope
- Direct firmware updates over USB (hardware uses stock UVC protocol).
- iOS USB OTG support (platform restriction for standard UVC drivers).
- Cloud user account syncing (prioritizing privacy & offline-first local storage).

---
*Last updated: 2026-10-29*

