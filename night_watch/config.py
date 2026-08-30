"""
Night Watch — Configuration & Detection Constants

All tunable detection parameters live here. Nothing is hardcoded in the
processing pipeline. Adjust these after testing against real recordings
(Phase 2).
"""

# ─── Audio Capture ─────────────────────────────────────────────────────────────

SAMPLE_RATE = 16000          # Hz — 16 kHz mono is sufficient for detection
CHANNELS = 1                 # Mono recording
AUDIO_DTYPE = "float32"

# ─── Framing ───────────────────────────────────────────────────────────────────

FRAME_DURATION_S = 1.0       # seconds per analysis frame
HOP_DURATION_S = 0.5         # seconds between frames (50 % overlap)
FRAME_SIZE = int(SAMPLE_RATE * FRAME_DURATION_S)   # 16 000 samples
HOP_SIZE = int(SAMPLE_RATE * HOP_DURATION_S)       #  8 000 samples

# ─── Rolling Baseline (Phase 2+) ──────────────────────────────────────────────

BASELINE_WINDOW_S = 60.0     # seconds of "normal" frames to keep
BASELINE_MAX_FRAMES = int(BASELINE_WINDOW_S / HOP_DURATION_S)  # ~120 frames

# ─── Anomaly Score Weights ─────────────────────────────────────────────────────
# Weight spectral flux most heavily (spec §3.4). These will be tuned in Phase 2.

W_RMS = 1.0
W_SPECTRAL_FLUX = 2.0       # 2× the others — key discriminator
W_SPECTRAL_CENTROID = 0.5   # supporting feature; noisy in low-signal conditions
W_ZCR = 0.5                 # supporting feature

# ── Minimum Standard Deviations (Baseline Floors) ─────────────────────────────
# Prevents tiny baseline stds from inflating z-scores on naturally-variable
# features.  Without these, a quiet room with a generator can produce
# centroid-delta z-scores of 7+ from normal wander.

MIN_STD_RMS = 0.001
MIN_STD_SPECTRAL_FLUX = 0.02
MIN_STD_CENTROID_DELTA = 150.0   # Hz — centroid wanders easily by 100-200 Hz
MIN_STD_ZCR = 0.01

# ─── Trigger Thresholds ───────────────────────────────────────────────────────

ANOMALY_THRESHOLD = 3.0      # combined z-score above which a frame is anomalous
TRIGGER_CONSECUTIVE = 2      # consecutive anomalous frames needed to start event
COOLDOWN_S = 2.0             # seconds below threshold before ending event
COOLDOWN_FRAMES = int(COOLDOWN_S / HOP_DURATION_S)  # ~4 frames

# ─── Buffering (Phase 3+) ─────────────────────────────────────────────────────

PRE_BUFFER_S = 5.0           # seconds of audio kept before event trigger
POST_BUFFER_S = 3.0          # seconds of audio appended after event ends

# ─── Event Merging (Phase 4+) ─────────────────────────────────────────────────

MERGE_GAP_S = 5.0            # merge events closer than this into one

# ─── Display (Phase 1) ────────────────────────────────────────────────────────

# Approximate max values for normalizing the real-time feature bars.
# These are just for visual scaling; they don't affect detection.
DISPLAY_RMS_MAX = 0.25
DISPLAY_FLUX_MAX = 1.0
DISPLAY_CENTROID_MAX = 6000.0   # Hz
DISPLAY_ZCR_MAX = 0.5
