# Phase 3: Camera Failover & Offline Resilience Pipeline — Context & Decisions

## Context
Phase 3 hardens the application against all hardware and network anomalies. It guarantees that if the smart glasses are abruptly unplugged, if USB bus errors occur, or if network connectivity is completely lost, the assistant never crashes, freezes, or leaves the visually impaired user without guidance.

## Locked Decisions

### 1. Fast-Fail Gemini Live Offline Degradation
- **Network Probe & Fast Interception:** Catch `SocketException`, `ClientException`, `HttpException`, DNS lookup failures, or network timeouts immediately on attempt 1.
- **Immediate Model Loop Abort:** Abort all 4 candidate model retry loops immediately upon network failure rather than waiting 8 seconds per model (eliminates 32-second silence).
- **Fast Local Return:** Return `'__FALLBACK_LOCAL__'` in `< 50ms`.
- **Zero API Error Spam:** Do not announce misleading "API key error" messages when the device is simply offline. Route smoothly to `VoiceCommandParser` and on-device TFLite/ML vision.

### 2. Auto-Restoring Obstacle Monitoring on Reconnect
- **Automatic Resume:** When smart glasses are reconnected and initialized, if obstacle alerts are enabled (`obstacleAlertsDefaultEnabled`), automatically restart `_startLiveObstacleMonitoring()` on the 2 fps in-memory UVC stream.
- **Leak-Free Resource Cleanup:** Safely stop the camera image stream and dispose the phone camera controller upon glasses reconnection to prevent memory leaks and camera hardware contention.

### 3. Physical USB Disconnect Mid-Inference Hardening
- **Defensive JNI & Frame Grab Protection:** Wrap `UvcCameraService.captureFrame()` and `_controller.takePicture()` in defensive try/catch handling.
- **PlatformException Recovery:** Instantly catch `PlatformException` or null controller errors if the cable is tugged mid-capture.
- **State Reset:** Reset `_isCapturing = false`, stop frame timers, transition `UvcConnectionState` to `disconnected`, invoke `_cleanupController()`, and trigger immediate phone camera fallback in `NavigationScreen`.

### 4. Offline Navigation & Favorite Places Fallback
- **Offline Place Resolution:** Resolve spoken destinations against saved favorite places (`storageService.getFavoritePlace`) and cached geocoded destinations (`storageService.getCachedDestination`).
- **Graceful Uncached Fallback Guidance:** If an uncached/unknown destination is requested without an internet connection, speak clear accessibility guidance: *"Operating offline. Routing is available for your saved favorite places, or I can guide you using compass bearing."*
- **Compass Guidance Activation:** Automatically activate direct compass bearing mode with distance and haptic pulses when OSRM walking router is unreachable.

### 5. Unified Multimodal RECALL_ITEM
- **Dual-Check Alignment:** Wire `[ACTION:RECALL_ITEM:<item>]` in `VoiceSessionCoordinator` to the same instant dual-check pipeline as offline `findItem`:
  1. Check live in-memory camera frame first with clock direction (*"I see your keys right now, on your left at 10 o'clock, about 1 meter ahead."*).
  2. Fall back to stored memory location if not currently visible (*"You saved that your keys are on the dining table. Would you like me to open the camera to look for them?"*).

---
*Created: 2026-10-29*

