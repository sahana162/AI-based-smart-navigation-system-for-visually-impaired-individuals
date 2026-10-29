# Phase 1: UVC Camera & Smart Glasses Stream Reliability — Context & Decisions

## Context
Phase 1 focuses on establishing an unbreakable hardware stream between the Android host and the wearable smart glasses over USB OTG, eliminating duplicate camera controllers, replacing slow disk-based frame grabs with an in-memory buffer, and ensuring seamless hot-plug recovery.

## Locked Decisions

### 1. Hardware & Resolution
- **Target Device:** YJX-C5 smart glasses camera (USB OTG standard UVC module).
- **Target Resolution:** Standard `640x480` for low ML inference latency, minimal memory footprint, and prevention of USB bus saturation.
- **Aspect & Format:** 4:3 standard aspect ratio, MJPEG/YUV decoding handled natively by `flutter_uvc_camera`.

### 2. Architecture Consolidation
- **Single Source of Truth:** `UvcCameraService` acts as the single authoritative provider / singleton for external smart glasses hardware state.
- **Elimination of Duplication:** `NavigationScreen` will no longer instantiate its own `UVCCameraController`. Both `NavigationScreen` and background vision consumers will subscribe to `UvcCameraService`.
- **State Machine:** Explicit camera state tracking:
  - `disconnected`
  - `connecting`
  - `connected`
  - `streaming`
  - `error`

### 3. Streaming & In-Memory Sampling
- **No Disk I/O:** Deprecate `takePicture()` temp file writes. Use direct frame byte extraction in-memory to prevent flash storage wear, garbage collection spikes, and file locking bugs.
- **Dual-Mode Frame Pipeline:**
  1. *Throttled Continuous Sampling:* Fixed 2 fps stream to drive background pedestrian safety, collision, and obstacle scanning without overheating the phone.
  2. *On-Demand Instant Capture:* Zero-latency synchronous snapshot extraction from the live stream buffer when the user asks voice questions (e.g., "What is in front of me?").

### 4. Hot-Plug & Disconnect Experience
- **100% Autonomous Fallback:** Blind and visually impaired users cannot see dialogs or tap modal buttons. When the USB cable drops, failover must be immediate and automatic.
- **Multimodal Alerts:**
  - Audible TTS announcement: *"Glasses disconnected. Switching to phone camera."*
  - Distinctive haptic feedback vibration pattern.
- **Automatic Re-engagement:** When `USB_DEVICE_ATTACHED` is received and permissions clear, the glasses stream immediately resumes and informs the user: *"Glasses reconnected."*

---
*Created: 2026-10-29*

