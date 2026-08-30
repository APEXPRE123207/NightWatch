"""
Night Watch — Event Recorder (Sections 3.5–3.8)

Manages the lifecycle of acoustic events:
  1. Maintains a pre-event circular buffer (5 s of raw audio).
  2. Detects event start (N consecutive anomalous frames).
  3. Accumulates event audio while the anomaly persists.
  4. Detects event end (cooldown period of normal frames).
  5. Appends post-buffer audio.
  6. Writes the assembled clip as a .wav file.
  7. Records the event in the SQLite database.
  8. Merges events that are too close together (Phase 4).
"""

import os
import wave
from datetime import datetime, timedelta

import numpy as np

from night_watch.audio_buffer import CircularAudioBuffer
from night_watch.config import (
    COOLDOWN_FRAMES,
    MERGE_GAP_S,
    POST_BUFFER_S,
    PRE_BUFFER_S,
    SAMPLE_RATE,
    HOP_DURATION_S,
    TRIGGER_CONSECUTIVE,
)
from night_watch.database import NightWatchDB


class EventRecorder:
    """
    Call ``process_chunk()`` once per hop with the raw audio chunk and
    the detector's anomaly result.  The recorder handles everything else.

    Parameters
    ----------
    db : NightWatchDB
    session_id : int
    output_dir : str
        Directory to write .wav clips into.
    """

    # Event states
    IDLE = "idle"
    RECORDING = "recording"            # actively recording an event
    COOLING_DOWN = "cooling_down"      # anomaly stopped, counting cooldown
    POST_BUFFERING = "post_buffering"  # capturing post-event audio
    MERGE_WINDOW = "merge_window"      # waiting to see if another anomaly merges

    def __init__(self, db: NightWatchDB, session_id: int, output_dir: str):
        self.db = db
        self.session_id = session_id
        self.output_dir = output_dir
        os.makedirs(output_dir, exist_ok=True)

        # Pre-event buffer: always running
        pre_samples = int(PRE_BUFFER_S * SAMPLE_RATE)
        self._pre_buffer = CircularAudioBuffer(pre_samples)

        # State machine
        self._state = self.IDLE
        self._consecutive_anomalies = 0
        self._cooldown_remaining = 0
        self._post_remaining = 0
        self._merge_remaining = 0

        # Current event data
        self._event_audio: list[np.ndarray] = []
        self._event_start_time: datetime | None = None
        self._event_peak_score: float = 0.0

        # Event counter for this session
        self._event_count = 0

        # Completed events log (for display)
        self.completed_events: list[dict] = []

    def process_chunk(self, chunk: np.ndarray, is_anomaly: bool, score: float) -> dict | None:
        """
        Feed one hop of raw audio + detection result.

        Returns
        -------
        dict or None
            If an event just finished saving, returns its metadata.
            Otherwise None.
        """
        now = datetime.now()
        finished_event = None

        if self._state == self.IDLE:
            self._pre_buffer.write(chunk)
            if is_anomaly:
                self._consecutive_anomalies += 1
                if self._consecutive_anomalies >= TRIGGER_CONSECUTIVE:
                    self._start_event(now, score)
            else:
                self._consecutive_anomalies = 0

        elif self._state == self.RECORDING:
            self._event_audio.append(chunk.copy())
            self._event_peak_score = max(self._event_peak_score, score)
            if not is_anomaly:
                self._cooldown_remaining = COOLDOWN_FRAMES
                self._state = self.COOLING_DOWN

        elif self._state == self.COOLING_DOWN:
            self._event_audio.append(chunk.copy())
            self._event_peak_score = max(self._event_peak_score, score)
            if is_anomaly:
                # Anomaly resumed — keep recording
                self._state = self.RECORDING
                self._cooldown_remaining = 0
            else:
                self._cooldown_remaining -= 1
                if self._cooldown_remaining <= 0:
                    # Cooldown expired — start post-buffer
                    post_frames = int(POST_BUFFER_S / HOP_DURATION_S)
                    self._post_remaining = post_frames
                    self._state = self.POST_BUFFERING

        elif self._state == self.POST_BUFFERING:
            self._event_audio.append(chunk.copy())
            self._post_remaining -= 1
            if self._post_remaining <= 0:
                # Post-buffer done — enter merge window instead of saving
                merge_frames = int(MERGE_GAP_S / HOP_DURATION_S)
                self._merge_remaining = merge_frames
                self._state = self.MERGE_WINDOW

        elif self._state == self.MERGE_WINDOW:
            # Keep accumulating audio (gap audio preserved if events merge)
            self._event_audio.append(chunk.copy())
            if is_anomaly:
                # New anomaly during merge window → merge into same event
                self._state = self.RECORDING
                self._merge_remaining = 0
                self._event_peak_score = max(self._event_peak_score, score)
            else:
                self._merge_remaining -= 1
                if self._merge_remaining <= 0:
                    # Merge window expired — no new anomaly, save the event.
                    # Trim the merge window audio (it was just silence/ambient)
                    merge_samples = int(MERGE_GAP_S * SAMPLE_RATE)
                    finished_event = self._end_event(now, trim_tail=merge_samples)

        return finished_event

    def _start_event(self, now: datetime, score: float) -> None:
        """Transition from IDLE → RECORDING."""
        self._event_start_time = now
        self._event_peak_score = score
        self._event_audio = []

        # Grab the pre-buffer
        pre_audio = self._pre_buffer.read_all()
        if len(pre_audio) > 0:
            self._event_audio.append(pre_audio)

        self._state = self.RECORDING
        self._consecutive_anomalies = 0

    def _end_event(self, now: datetime, trim_tail: int = 0) -> dict:
        """Finalize and save the current event."""
        self._event_count += 1

        # Assemble the full clip
        if self._event_audio:
            full_audio = np.concatenate(self._event_audio)
        else:
            full_audio = np.array([], dtype=np.float32)

        # Trim merge-window silence from the tail if not merged
        if trim_tail > 0 and len(full_audio) > trim_tail:
            full_audio = full_audio[:-trim_tail]

        duration = len(full_audio) / SAMPLE_RATE

        # Save .wav
        filename = f"event_{self._event_count:04d}.wav"
        clip_path = os.path.join(self.output_dir, filename)
        self._write_wav(clip_path, full_audio)

        # Record in database
        start_str = self._event_start_time.isoformat() if self._event_start_time else now.isoformat()
        end_str = now.isoformat()

        event_id = self.db.insert_event(
            session_id=self.session_id,
            start_time=start_str,
            end_time=end_str,
            duration_seconds=round(duration, 2),
            peak_score=round(self._event_peak_score, 2),
            clip_path=clip_path,
        )

        event_info = {
            "id": event_id,
            "number": self._event_count,
            "start_time": self._event_start_time,
            "end_time": now,
            "duration": duration,
            "peak_score": self._event_peak_score,
            "clip_path": clip_path,
        }
        self.completed_events.append(event_info)

        # Reset for next event
        self._event_audio = []
        self._event_start_time = None
        self._event_peak_score = 0.0
        self._state = self.IDLE
        self._pre_buffer.clear()

        return event_info

    def finalize(self) -> None:
        """Call at session end — save any in-progress event."""
        if self._state in (self.RECORDING, self.COOLING_DOWN,
                           self.POST_BUFFERING, self.MERGE_WINDOW):
            self._end_event(datetime.now())

    @property
    def state(self) -> str:
        return self._state

    @property
    def event_count(self) -> int:
        return self._event_count

    # ── WAV writer ──────────────────────────────────────────────────────────

    @staticmethod
    def _write_wav(path: str, audio: np.ndarray) -> None:
        """Write float32 mono audio to a 16-bit PCM .wav file."""
        # Convert float32 [-1, 1] to int16
        audio_clamped = np.clip(audio, -1.0, 1.0)
        pcm = (audio_clamped * 32767).astype(np.int16)

        with wave.open(path, "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)  # 16-bit
            wf.setframerate(SAMPLE_RATE)
            wf.writeframes(pcm.tobytes())


