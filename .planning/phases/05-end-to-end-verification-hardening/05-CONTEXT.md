# Phase 5: End-to-End Verification & Real-World Hardening — Context & Decisions

## Context
Phase 5 is the final milestone of the roadmap. It conducts rigorous, comprehensive automated testing and real-world edge case validation across all requirements delivered in Phases 1 through 4: UVC smart glasses stream reliability, in-memory TFLite byte inference, instant dual-check spatial recall, fast-fail offline degradation, defensive USB cord disconnect handling, zero-latency local query fast-paths, hazard audio preemption, and accessibility compliance.

## Locked Decisions

### 1. Hardware Disconnect & Jiggle Edge Cases
- **Mid-Inference Disconnect Test:** Validate that an abrupt `PlatformException` or controller nulling during active `captureFrame()` cleanly resets `_isCapturing = false`, transitions `UvcConnectionState.disconnected`, stops frame timers, and triggers phone camera fallback without throwing unhandled exceptions.
- **Hot-Plug Reconnection Test:** Validate that reconnecting smart glasses disposes the phone camera image stream and controller, restores UVC preview, and automatically restarts 2 fps obstacle monitoring.

### 2. Network Drop & Cloud Degradation Validation
- **Fast-Fail Interception Test:** Validate that `GeminiLiveService.converse()` intercepts `SocketException` or `ClientException` on attempt 1, terminates the candidate model loop immediately, and returns `'__FALLBACK_LOCAL__'` in `< 50ms`.
- **Offline Voice Parsing Test:** Validate that `VoiceSessionCoordinator` cleanly routes offline voice commands to `VoiceCommandParser` without speaking false API key errors.
- **Offline Routing Fallback Test:** Validate that `PedestrianNavigationService` resolves cached favorite destinations offline and activates direct compass bearing mode when Nominatim geocoding or OSRM fail.

### 3. Low-Latency Preemption & Echo Cancellation
- **Instant Preemption Test:** Validate that `TtsService.speak()` with `TtsPriority.hazard` or `TtsPriority.emergency` immediately halts ongoing lower-priority speech (`_tts.stop()`), purges lower-priority queue items, and broadcasts `onSpeechStarting`.
- **Mic Muting Window Test:** Validate that `VoiceSessionCoordinator` pauses `speechService` when hazard audio starts and enforces a 300ms acoustic grace period before listening can resume.

### 4. Spatial Phrasing & Directional Haptics
- **Clock Phrasing Unit Tests:** Validate `DetectedVisionItem.formatConciseDescription()` and `formatSpatialDescription()` across all clock positions (10, 11, 12, 1, 2 o'clock) in both English and Kannada.
- **Directional Haptics Test:** Validate that `VoiceSessionCoordinator.triggerDirectionalHaptic()` executes without errors for left, center (double-pulse), and right tactile patterns.

### 5. Accessibility Compliance
- **Semantics & Target Ergonomics:** Validate that key screens (`HomeScreen`, `SettingsScreen`, `FeatureDetailScreen`) provide accessible labels, large touch targets, and clean semantics for screen reader users.

---
*Created: 2026-10-29*

