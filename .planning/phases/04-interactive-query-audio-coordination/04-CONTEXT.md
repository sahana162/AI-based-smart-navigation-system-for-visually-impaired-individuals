# Phase 4: Interactive Query & Low-Latency Audio Coordination — Context & Decisions

## Context
Phase 4 focuses on achieving sub-500ms voice query latency for real-time spatial navigation and safety, coupled with preemption and directional sensory cues. When a visually impaired user asks *"What is in front of me?"*, *"Any obstacles?"*, or *"Where are my keys?"*, the assistant must provide immediate, front-loaded directional guidance with directional haptic and audio feedback without waiting for cloud roundtrips.

## Locked Decisions

### 1. Zero-Latency Fast-Path by Default
- **Local Fast-Path for Safety & Spatial Queries:** For urgent visual and obstacle queries:
  - `"What is ahead?"`, `"What's in front of me?"`, `"Describe surroundings"`, `"Any obstacles?"`, `"Obstacle check"`
  - `"Where is my [item]?"`, `"Find my [item]"`
  - `"What note is this?"`, `"Check currency"`
  - Route directly to local in-memory frame buffer (`UvcCameraService.getLatestFrame()`) and on-device TFLite models, achieving `< 350ms` response time.
- **Conversational Open-Ended Inquiries:** Open-ended and general reasoning queries continue to be handled by multimodal Gemini Live cloud service.

### 2. Audio Preemption & Echo Cancellation
- **Immediate Preemption:** Tier 0 (`emergency`) and Tier 1 (`hazard`) alerts instantly call `_tts.stop()`, clear all lower-priority ambient speech in the queue, and immediately play the hazard warning with heavy haptics.
- **Mic Mute Window:** Automatically pause speech recognition (`speechService.stopListening()`) during hazard and safety announcements, resuming with a 300ms acoustic grace period after TTS completion to prevent acoustic feedback loops.

### 3. Front-Loaded, Concise Spatial Phrasing
- **Terse, Punchy Format:** Fast-path obstacle and item queries front-load actionable data:
  - Format: `"[Item/Obstacle]: [Clock position], [Distance]"`
  - Example: *"Backpack: 10 o'clock, 1.5 meters."*
  - Example Center: *"Chair: 12 o'clock, 1 meter directly ahead."*
  - Kannada format: `"[ವಸ್ತು]: [ಗಂಟೆಯ ದಿಕ್ಕು], [ದೂರ]"` (e.g., *"ಬ್ಯಾಗ್: 10 ಗಂಟೆ, 1.5 ಮೀಟರ್."*)
- Conversational polite phrasing is reserved for non-urgent open dialogue.

### 4. Directional Haptic & Earcon Feedback
- **Clock-Based Directional Haptics:**
  - 10–11 o'clock (Left): Left-biased vibration pattern (single sharp pulse).
  - 12 o'clock (Center): Double heavy impact pulse.
  - 1–2 o'clock (Right): Two light clicks / right-biased pattern.
- **Sonar Earcons:** Immediate auditory click sound (`SystemSound.play(SystemSoundType.click)`) accompanies the directional haptic cue, allowing the user to sense orientation before speech finishes.

---
*Created: 2026-10-29*
