# Phase 2: Real-Time Vision & Spatial Memory Integration — Context & Decisions

## Context
Phase 2 bridges live object detection with conversational spatial memory (`RememberedItem`). It connects the smart glasses' continuous 2 fps in-memory frame stream directly to `ObjectDetectorService`, introduces rich spatial clock directions, establishes an instant dual-check pipeline for item search, and prevents speech fatigue with smart cooldowns.

## Locked Decisions

### 1. Unified Continuous Detection Pipeline
- **Smart Glasses Stream Connection:** Wire `UvcCameraService.onFrameStream` directly into `ObjectDetectorService.detectObjectsFromBytes()`.
- **Shared Pipeline:** Ensure the same inference, hazard analysis, and audio announcements fire whether the user is wearing the smart glasses or using the phone camera fallback.
- **Pure In-Memory:** Zero disk writes for continuous 2 fps background detection.

### 2. Instant Dual-Check Query Flow ("Where is my [item]?")
- **Step 1 (Immediate Live Scan):** First check the current in-memory camera frame from the active sensor (smart glasses or phone).
  - If visible in frame: speak real-time location immediately (*"I see your keys right now, on your left at 10 o'clock, about 1 meter ahead."*).
- **Step 2 (Memory Fallback):** If not detected in the current camera view, fall back to the saved `RememberedItem` location in `StorageService`:
  - Speak stored memory (*"Not visible in your current view. You last remembered placing it on the dining table."*).

### 3. Spatial & Directional Phrasing (Option C: Combined)
- **Natural Relative + Clock:**
  - Center: *"Keys directly ahead, about 1.5 meters away."*
  - Left: *"Keys on your left, 10 o'clock, about 1 meter away."*
  - Right: *"Keys on your right, 2 o'clock, about 1.2 meters away."*
- **Distance Estimation:** Bounding box height relative to image dimension determines approximate distance in meters and step counts (~0.7m per step).

### 4. Audio De-Duplication & Fatigue Protection
- **Static Suppression Window:** 12-second suppression cooldown per detected object class to prevent repeating non-emergency announcements (e.g. standing near a chair).
- **Critical Path Bypass:** If an object is detected in the direct pedestrian forward path (center) within `< 1.2 meters`, immediately bypass the cooldown and announce emergency hazard.

---
*Created: 2026-10-29*

