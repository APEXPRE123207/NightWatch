#!/usr/bin/env python3
"""
Night Watch — Phase 3: Event Buffering + Clip Saving (Desktop)

Builds on Phase 2 by adding:
  - 5-second pre-event circular buffer (always running)
  - Automatic .wav clip saving when events are detected
  - SQLite database logging (sessions + events)
  - Event state machine (idle → recording → cooldown → post-buffer → save)

Clips and database are stored under:
    ./night_watch_data/<session_id>/

Usage
-----
    python phase3_live.py

Press Ctrl+C to stop.  Any in-progress event is saved on exit.
"""

import os
import sys
import time
from datetime import datetime

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))

from night_watch.config import (
    SAMPLE_RATE,
    HOP_SIZE,
    FRAME_SIZE,
    HOP_DURATION_S,
    ANOMALY_THRESHOLD,
    DISPLAY_RMS_MAX,
    DISPLAY_FLUX_MAX,
    DISPLAY_CENTROID_MAX,
    DISPLAY_ZCR_MAX,
    W_RMS,
    W_SPECTRAL_FLUX,
    W_SPECTRAL_CENTROID,
    W_ZCR,
)
from night_watch.feature_extractor import FeatureExtractor
from night_watch.audio_source import DesktopAudioSource
from night_watch.detector import AnomalyDetector
from night_watch.database import NightWatchDB
from night_watch.event_recorder import EventRecorder


# ── Display ─────────────────────────────────────────────────────────────────────

BAR_WIDTH = 25
SCORE_BAR_WIDTH = 35

RESET = "\033[0m"
DIM = "\033[2m"
BOLD = "\033[1m"
GREEN = "\033[92m"
YELLOW = "\033[93m"
RED = "\033[91m"
CYAN = "\033[96m"
MAGENTA = "\033[95m"
WHITE = "\033[97m"
BG_RED = "\033[41m"
BG_GREEN = "\033[42m"
BG_YELLOW = "\033[43m"
BG_MAGENTA = "\033[45m"


def _bar(value, max_val, width=BAR_WIDTH):
    ratio = max(0.0, min(1.0, value / max_val))
    filled = int(ratio * width)
    c = GREEN if ratio < 0.33 else (YELLOW if ratio < 0.66 else RED)
    return c + "█" * filled + DIM + "░" * (width - filled) + RESET


def _score_bar(score, threshold, width=SCORE_BAR_WIDTH):
    max_val = threshold * 3
    ratio = max(0.0, min(1.0, score / max_val))
    thresh_pos = max(0, min(width - 1, int((threshold / max_val) * width)))
    filled = int(ratio * width)
    chars = []
    for i in range(width):
        if i < filled:
            chars.append((RED if score > threshold else GREEN) + "█")
        elif i == thresh_pos:
            chars.append(YELLOW + "┃")
        else:
            chars.append(DIM + "░")
    return "".join(chars) + RESET


def _z_ind(z):
    az = abs(z)
    c = GREEN if az < 1.0 else (YELLOW if az < 2.0 else RED)
    return f"{c}{z:+6.2f}{RESET}"


def _clear(n):
    for _ in range(n):
        sys.stdout.write("\033[A\033[2K")


DISPLAY_LINES = 17


def print_header(session_id, data_dir):
    print()
    print(f"{BOLD}  ╔══════════════════════════════════════════════════════════════════╗{RESET}")
    print(f"{BOLD}  ║   🌙  NIGHT WATCH — Phase 3: Event Recording                   ║{RESET}")
    print(f"{BOLD}  ╚══════════════════════════════════════════════════════════════════╝{RESET}")
    print()
    print(f"  {DIM}Session #{session_id}  |  Data: {data_dir}{RESET}")
    print(f"  {DIM}Press Ctrl+C to stop{RESET}")
    print()


def print_dashboard(features, result, recorder, frame_count, elapsed, anomaly_count):
    if frame_count > 1:
        _clear(DISPLAY_LINES)

    rms = features["rms"]
    flux = features["spectral_flux"]
    centroid = features["spectral_centroid"]
    zcr = features["zcr"]
    z = result.z_scores
    score = result.score
    mins, secs = divmod(int(elapsed), 60)

    # Status line
    state = recorder.state
    if result.warming_up:
        status = f"  {BG_YELLOW}{BOLD} ⏳ WARMING UP ({result.baseline_frames} frames) {RESET}"
    elif state in ("recording", "cooling_down", "post_buffering"):
        status = f"  {BG_RED}{WHITE}{BOLD} ● REC  {RESET}  {RED}Event in progress...{RESET}  score: {score:.2f}"
    elif state == "merge_window":
        status = f"  {BG_MAGENTA}{WHITE}{BOLD} ⏳ MERGE WINDOW {RESET}  {DIM}waiting for nearby events...{RESET}"
    elif result.is_anomaly:
        status = f"  {BG_RED}{WHITE}{BOLD} ⚠  ANOMALY  {RESET}  score: {RED}{score:.2f}{RESET}"
    else:
        status = f"  {BG_GREEN}{WHITE}{BOLD}  ✓ NORMAL   {RESET}  score: {GREEN}{score:.2f}{RESET}"

    print(status)
    print()

    # Features
    print(f"  {CYAN}RMS Energy   {RESET}{rms:8.5f}  {_bar(rms, DISPLAY_RMS_MAX)}  z={_z_ind(z.get('rms', 0))}")
    print(f"  {MAGENTA}Spec. Flux   {RESET}{flux:8.5f}  {_bar(flux, DISPLAY_FLUX_MAX)}  z={_z_ind(z.get('spectral_flux', 0))}")
    print(f"  {YELLOW}Δ Centroid   {RESET}{centroid:7.0f} Hz {_bar(centroid, DISPLAY_CENTROID_MAX)}  z={_z_ind(z.get('centroid_delta', 0))}")
    print(f"  {GREEN}ZCR          {RESET}{zcr:8.5f}  {_bar(zcr, DISPLAY_ZCR_MAX)}  z={_z_ind(z.get('zcr', 0))}")
    print()

    # Score bar
    print(f"  {BOLD}Score{RESET}  {score:6.2f}  {_score_bar(score, ANOMALY_THRESHOLD)}  {DIM}(thresh: {ANOMALY_THRESHOLD}){RESET}")
    print()

    # Event info
    saved = recorder.event_count
    last_event_str = ""
    if recorder.completed_events:
        last = recorder.completed_events[-1]
        t = last["start_time"].strftime("%H:%M:%S") if last["start_time"] else "?"
        last_event_str = f"  |  Last: {t} ({last['duration']:.1f}s)"

    print(f"  {DIM}Frame: {frame_count}  |  {mins:02d}:{secs:02d}  |  State: {state.upper()}"
          f"  |  Saved: {saved} events{last_event_str}{RESET}")
    print()

    # Recent events list
    events = recorder.completed_events[-3:]  # show last 3
    if events:
        print(f"  {BOLD}Recent events:{RESET}")
        for ev in events:
            t = ev["start_time"].strftime("%H:%M:%S") if ev["start_time"] else "?"
            print(f"    {DIM}#{ev['number']}{RESET}  {t}  {ev['duration']:.1f}s  "
                  f"peak={ev['peak_score']:.1f}  {DIM}{os.path.basename(ev['clip_path'])}{RESET}")
    else:
        print(f"  {DIM}No events recorded yet{RESET}")
        print(f"  {DIM}{RESET}")
        print(f"  {DIM}{RESET}")

    print()


# ── Main ────────────────────────────────────────────────────────────────────────

def main():
    if sys.platform == "win32":
        os.system("")

    # Set up data directory
    base_dir = os.path.join(os.path.dirname(__file__), "night_watch_data")
    db_path = os.path.join(base_dir, "night_watch.db")
    db = NightWatchDB(db_path)
    session_id = db.create_session()
    clip_dir = os.path.join(base_dir, str(session_id))

    extractor = FeatureExtractor(SAMPLE_RATE)
    detector = AnomalyDetector()
    recorder = EventRecorder(db, session_id, clip_dir)
    source = DesktopAudioSource(sample_rate=SAMPLE_RATE, chunk_size=HOP_SIZE)

    frame_buffer = np.zeros(FRAME_SIZE, dtype=np.float32)

    print_header(session_id, clip_dir)
    for _ in range(DISPLAY_LINES):
        print()

    frame_count = 0
    anomaly_count = 0
    start_time = time.time()

    try:
        with source:
            while True:
                chunk = source.read_chunk(timeout=5.0)

                # Build overlapping frame
                frame_buffer[:FRAME_SIZE - HOP_SIZE] = frame_buffer[HOP_SIZE:]
                frame_buffer[FRAME_SIZE - HOP_SIZE:] = chunk

                frame_count += 1
                if frame_count < 2:
                    extractor.extract(frame_buffer)
                    recorder.process_chunk(chunk, False, 0.0)
                    continue

                features = extractor.extract(frame_buffer)
                result = detector.process(features)

                if result.is_anomaly:
                    anomaly_count += 1

                # Feed the event recorder
                finished = recorder.process_chunk(chunk, result.is_anomaly, result.score)
                if finished:
                    t = finished["start_time"].strftime("%H:%M:%S")
                    # A newline announcement that won't be overwritten
                    pass  # The dashboard shows it

                elapsed = time.time() - start_time
                print_dashboard(features, result, recorder, frame_count, elapsed, anomaly_count)

    except KeyboardInterrupt:
        recorder.finalize()
        elapsed = time.time() - start_time
        db.end_session(session_id, int(elapsed))
        db.close()

        mins, secs = divmod(int(elapsed), 60)
        print(f"\n  {BOLD}Session #{session_id} ended.{RESET}")
        print(f"  Duration: {mins:02d}:{secs:02d}  |  Events saved: {recorder.event_count}")
        if recorder.completed_events:
            print(f"\n  {BOLD}All events:{RESET}")
            for ev in recorder.completed_events:
                t = ev["start_time"].strftime("%H:%M:%S") if ev["start_time"] else "?"
                print(f"    #{ev['number']}  {t}  {ev['duration']:.1f}s  "
                      f"peak={ev['peak_score']:.1f}  → {ev['clip_path']}")
        print(f"\n  Database: {db_path}")
        print(f"  Clips:    {clip_dir}")


if __name__ == "__main__":
    main()
