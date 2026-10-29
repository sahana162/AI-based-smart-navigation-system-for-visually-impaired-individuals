# Roadmap: AI-Based Smart Navigation Assistant

## Milestone 1: Core Glasses Vision & Resilient Spatial Memory

### Progress

| Phase | Name | Status | Plans | Target Date |
|-------|------|--------|-------|-------------|
| 1 | UVC Camera & Smart Glasses Stream Reliability | Completed ✓ | 2 plans (01-01, 01-02) | 2026-10-29 |
| 2 | Real-Time Vision & Spatial Memory Integration | Completed ✓ | 2 plans (02-01, 02-02) | 2026-10-29 |
| 3 | Camera Failover & Offline Resilience Pipeline | Completed ✓ | 2 plans (03-01, 03-02) | 2026-10-29 |
| 4 | Interactive Query & Low-Latency Audio Coordination | Completed ✓ | 2 plans (04-01, 04-02) | 2026-10-29 |
| 5 | End-to-End Verification & Real-World Hardening | Completed ✓ | 2 plans (05-01, 05-02) | 2026-10-29 |

---

### Phases

#### Phase 1: UVC Camera & Smart Glasses Stream Reliability
**Goal:** Solidify connection lifecycle, USB permission prompt, hot-plug/unplug event handling, and steady frame capture from external smart glasses without memory leaks or frozen frames.
**Requirements:** R1.1, R1.2, R1.3, R1.4
- [x] Inspect and harden `UvcCameraService` state machine (connecting, streaming, disconnected, error).
- [x] Add explicit USB device attached/detached broadcast receiver / listener hooks in Android manifest & service.
- [x] Implement leak-free, throttled frame capture buffer for continuous vision feed.
- [x] Provide clear audio & state indicators when glasses connect/disconnect.

#### Phase 2: Real-Time Vision & Spatial Memory Integration
**Goal:** Bridge live object detector outputs with conversational spatial memory (`RememberedItem` & `StorageService`), enabling the app to actively track and locate items in the visual field.
**Requirements:** R2.1, R2.2, R2.4
- [x] Extend `VisionService` and `ObjectDetectorService` to calculate relative spatial positions (horizontal angle, clock position, relative distance) of detected objects.
- [x] Integrate live object detection stream with `StorageService.getRememberedItems()` for real-time item cross-referencing.
- [x] Implement spatial memory tagging: allow user to capture and store current camera snapshot location when placing an item down.
- [x] Add detection de-duplication and cooldown logic to eliminate auditory noise.

#### Phase 3: Camera Failover & Offline Resilience Pipeline
**Goal:** Guarantee system never fails or goes blind. If smart glasses unplug, seamlessly fall back to phone camera; if network drops, continue full local navigation and object detection.
**Requirements:** R3.1, R3.2, R3.3, R3.4
- [x] Implement automatic hot-swap camera fallback: UVC -> Smartphone back camera with instant spoken notification.
- [x] Auto-restore UVC stream when smart glasses are reconnected without screen reload.
- [x] Harden offline mode across `VoiceSessionCoordinator`, `GeminiLiveService`, and `VisionService` to gracefully route to local TFLite / ML Kit without exceptions or delays.
- [x] Test and enforce zero unhandled crashes on sudden USB disconnect during active inferencing.

#### Phase 4: Interactive Query & Low-Latency Audio Coordination
**Goal:** Provide sub-500ms voice query responses ("Where are my keys?", "What is in front of me?") with crisp directional audio cues and prioritized interrupt handling.
**Requirements:** R2.3, R3.4
- [x] Connect `VoiceSessionCoordinator` and `voice_command_parser` directly to real-time spatial memory search.
- [x] Optimize TTS speech output pipeline: high-priority safety/obstacle alerts interrupt low-priority descriptions.
- [x] Benchmark and optimize end-to-end latency from user voice prompt to audio directional answer.

#### Phase 5: End-to-End Verification & Real-World Hardening
**Goal:** Rigorously verify all edge cases (cable jiggle, backgrounding, network loss, dark environments, noisy background speech) and run user acceptance validation.
**Requirements:** All V1 requirements
- [x] Execute automated unit and integration tests across services.
- [x] Validate physical USB disconnect & reconnect scenarios on device.
- [x] Verify accessibility compliance: high contrast, screen reader semantics, and clear audio prompts.

---
*Last updated: 2026-10-29*

