# Project Memory: AI-Based Smart Navigation Assistant

Permanent memory log capturing core architectural principles, decisions, and lessons learned across milestone deliveries.

---

## 🏛️ Milestone 1: Core Glasses Vision & Resilient Spatial Memory
**Completed:** 2026-10-29  
**Phases Covered:** Phase 1 through Phase 5 (10 Execution Plans)  
**Verification:** 98 Automated Tests Passing (100% success rate), 0 Analyzer Issues

---

### 1. Architectural Principles & Invariants

#### A. UVC Smart Glasses & Hardware Stream Management
- **Single Controller Invariant:** All UVC camera interactions must be strictly centralized through the `UvcCameraService` singleton. Instantiating concurrent or secondary `UVCCameraController` instances corrupts the native JNI session and crashes the Android camera driver.
- **Zero Flash Disk I/O for Streaming:** Continuous 2 fps inference feeds process strictly in-memory using `Uint8List` byte buffers. Eliminating flash storage writes avoids disk latency spikes, flash memory wear, and GC thrashing.
- **Defensive JNI & Cord-Pull Protection:** Sudden cable pulls mid-frame must be defended with try/catch blocks catching `PlatformException` and native drops inside `captureFrame()`. State immediately resets to disconnected, clearing capture locks and activating phone camera failover.
- **Auto-Restoring In-Memory Loop:** When smart glasses are re-plugged, the live obstacle monitoring loop resumes seamlessly on the 2 fps UVC stream while disposing the phone camera controller cleanly to avoid memory leaks.

#### B. On-Device Vision & Spatial Orientation
- **Direct Byte Inference:** TFLite SSD MobileNet operates directly on raw memory byte buffers (`detectObjectsFromBytes`), bypassing file system decoders.
- **Clock Direction & Distance Phrasing:** Relative clock directions (10 to 2 o'clock) paired with distance metrics (e.g., `"backpack: 10 o'clock, 1.5m"`) provide the most intuitive spatial orientation for visually impaired users.
- **Fatigue Cooldown with Hazard Bypass:** A 12-second audio repetition suppression window prevents overwhelming auditory fatigue, while immediately bypassing cooldowns for forward-cone obstacles closer than 1.2 meters.

#### C. Cloud Degradation & Low-Latency Fallbacks
- **Fast-Fail Cloud Degradation (< 50ms):** When offline or when network packets drop (`SocketException`, `ClientException`, timeouts), `GeminiLiveService` immediately aborts candidate model retry loops on attempt 1, returning `'__FALLBACK_LOCAL__'` to `VoiceCommandParser` without speaking false API key errors.
- **Zero-Latency Local Fast-Path (< 350ms):** Time-sensitive visual safety queries ("What is ahead?", "Where are my keys?") take an instant local path using the latest in-memory camera frame without network roundtrips.
- **Offline Pedestrian Fallback:** Saved favorite places route offline from `StorageService`; uncached destinations automatically fall back to live compass bearing guidance and directional tactile pulses.

#### D. Audio Safety & Accessibility Compliance
- **Hazard Priority Preemption:** Tier 0 (emergency) and Tier 1 (hazard) alerts immediately call `TtsService.stop()`, clear lower-priority queues, and announce the hazard with directional haptics.
- **Microphone Mute Window & Acoustic Grace Period:** Active microphone listening pauses during hazard alerts plus a 300ms acoustic grace period to prevent speaker-to-mic echo loops.
- **True Assistive UI Architecture:** Navigation (Zone 1), Voice Mic (Zone 2), and Safety Dock (Zone 3) adhere to $\ge 48\times 48$ dp minimum touch targets and clean accessibility semantics.

---

### 2. ⚠️ Hidden Gotchas & Critical Lessons Learned

1. **Android USB OTG & UVC Permission Behavior:**
   - On Android, connecting a UVC camera via OTG prompts a native OS USB permission dialog. If the user accidentally jiggles or disconnects the cable, permissions can reset or invalidate the underlying file descriptor.
   - *Lesson:* The code must always re-verify USB permissions on `USB_DEVICE_ATTACHED` without assuming the previous permission grant persists across disconnect cycles.

2. **Frame Buffer Byte Sizing & Truncated Packets:**
   - UVC video packets over OTG can occasionally deliver incomplete, corrupt, or zero-byte frames during hot-plug handshakes.
   - *Lesson:* Any frame buffer with length `< 1000` bytes must be dropped immediately before passing into TFLite decoding or bitmap conversion to prevent native segmentation faults and image decompression crashes.

3. **TalkBack vs. Custom Audio Collisions:**
   - When TalkBack or other device screen readers are active alongside our internal `TtsService`, speech collisions and double-utterances can occur.
   - *Lesson:* Screen `Semantics` must focus strictly on descriptive accessibility labels for static UI controls, while dynamic real-time hazard warnings remain strictly managed by `TtsService`'s priority queue to prevent spoken speech collisions.

4. **Model Resiliency & Fallback Guarantee:**
   - Never allow any unhandled HTTP, WebSocket, or JNI exception to bubble up to the UI isolate.
   - *Lesson:* Every hardware or cloud interface must have a local, offline-capable fallback path ready to activate in under 50ms without user intervention or cryptic error announcements.

---
*Persisted via `/gsd-commit-memory` on 2026-10-29*

