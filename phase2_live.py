#!/usr/bin/env python3
"""
Night Watch — Phase 2: Baseline + Anomaly Detection (Desktop)

Builds on Phase 1 by adding:
  - Rolling baseline that adapts to steady background noise
  - Per-feature z-scores against the baseline
  - Weighted anomaly score (spectral flux weighted 2×)
  - Real-time NORMAL / ANOMALY status display

The first ~10 seconds are a warm-up period where the baseline is learning
the room's ambient sound profile.  After that, deviations are flagged.

Usage
-----
    python phase2_live.py                # console dashboard
    python phase2_live.py --csv out.csv  # also log to CSV for tuning

Test against: fan, AC, snoring-like sounds (should stay NORMAL),
then talking, coughing, tapping, door (should spike ANOMALY).

Press Ctrl+C to stop.
"""

import argparse
import csv
import os
import sys
import time

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


# ── Display constants ───────────────────────────────────────────────────────────

BAR_WIDTH = 25
SCORE_BAR_WIDTH = 40
MAX_ANOMALY_DISPLAY = ANOMALY_THRESHOLD * 3  # scale the score bar

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


def _bar(value: float, max_val: float, width: int = BAR_WIDTH) -> str:
    ratio = max(0.0, min(1.0, value / max_val))
    filled = int(ratio * width)
    if ratio < 0.33:
        colour = GREEN
    elif ratio < 0.66:
        colour = YELLOW
    else:
        colour = RED
    return colour + "█" * filled + DIM + "░" * (width - filled) + RESET


def _score_bar(score: float, threshold: float, width: int = SCORE_BAR_WIDTH) -> str:
    """Score bar with a threshold marker."""
    max_val = MAX_ANOMALY_DISPLAY
    ratio = max(0.0, min(1.0, score / max_val))
    thresh_pos = max(0, min(width - 1, int((threshold / max_val) * width)))
    filled = int(ratio * width)

    bar_chars = []
    for i in range(width):
        if i < filled:
            if score > threshold:
                bar_chars.append(RED + "█")
            else:
                bar_chars.append(GREEN + "█")
        elif i == thresh_pos:
            bar_chars.append(YELLOW + "┃")
        else:
            bar_chars.append(DIM + "░")
    return "".join(bar_chars) + RESET


def _z_indicator(z: float) -> str:
    """Colour-coded z-score."""
    az = abs(z)
    if az < 1.0:
        return f"{GREEN}{z:+6.2f}{RESET}"
    elif az < 2.0:
        return f"{YELLOW}{z:+6.2f}{RESET}"
    else:
        return f"{RED}{z:+6.2f}{RESET}"


def _clear_lines(n: int) -> None:
    for _ in range(n):
        sys.stdout.write("\033[A\033[2K")


DISPLAY_LINES = 14  # total lines in the feature block


def print_header() -> None:
    print()
    print(f"{BOLD}  ╔══════════════════════════════════════════════════════════════════╗{RESET}")
    print(f"{BOLD}  ║   🌙  NIGHT WATCH — Phase 2: Anomaly Detection                 ║{RESET}")
    print(f"{BOLD}  ╚══════════════════════════════════════════════════════════════════╝{RESET}")
    print()
    print(f"  {DIM}Weights: RMS={W_RMS}  Flux={W_SPECTRAL_FLUX}  Centroid={W_SPECTRAL_CENTROID}  ZCR={W_ZCR}  |  Threshold={ANOMALY_THRESHOLD}{RESET}")
    print(f"  {DIM}Press Ctrl+C to stop{RESET}")
    print()


def print_dashboard(features, result, frame_count, elapsed, anomaly_count) -> None:
    if frame_count > 1:
        _clear_lines(DISPLAY_LINES)

    rms = features["rms"]
    flux = features["spectral_flux"]
    centroid = features["spectral_centroid"]
    zcr = features["zcr"]
    z = result.z_scores
    score = result.score

    mins, secs = divmod(int(elapsed), 60)

    # Status banner
    if result.warming_up:
        status = f"  {BG_YELLOW}{BOLD} ⏳ WARMING UP ({result.baseline_frames} frames) {RESET}"
    elif result.is_anomaly:
        status = f"  {BG_RED}{WHITE}{BOLD} ⚠  ANOMALY  {RESET}  score: {RED}{score:.2f}{RESET}"
    else:
        status = f"  {BG_GREEN}{WHITE}{BOLD}  ✓ NORMAL   {RESET}  score: {GREEN}{score:.2f}{RESET}"

    print(status)
    print()

    # Feature readouts with z-scores
    print(f"  {CYAN}RMS Energy   {RESET}{rms:8.5f}  {_bar(rms, DISPLAY_RMS_MAX)}  z={_z_indicator(z.get('rms', 0))}")
    print(f"  {MAGENTA}Spec. Flux   {RESET}{flux:8.5f}  {_bar(flux, DISPLAY_FLUX_MAX)}  z={_z_indicator(z.get('spectral_flux', 0))}")
    print(f"  {YELLOW}Δ Centroid   {RESET}{centroid:7.0f} Hz {_bar(centroid, DISPLAY_CENTROID_MAX)}  z={_z_indicator(z.get('centroid_delta', 0))}")
    print(f"  {GREEN}ZCR          {RESET}{zcr:8.5f}  {_bar(zcr, DISPLAY_ZCR_MAX)}  z={_z_indicator(z.get('zcr', 0))}")
    print()

    # Anomaly score bar
    print(f"  {BOLD}Score{RESET}  {score:6.2f}  {_score_bar(score, ANOMALY_THRESHOLD)}  {DIM}(threshold: {ANOMALY_THRESHOLD}){RESET}")
    print()

    # Footer
    print(f"  {DIM}Frame: {frame_count}  |  Elapsed: {mins:02d}:{secs:02d}  |  Anomalies: {anomaly_count}  |  Baseline: {result.baseline_frames} frames{RESET}")
    print()


# ── Main loop ───────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="Night Watch Phase 2 — anomaly detection")
    parser.add_argument("--csv", type=str, default=None, help="Log features + scores to CSV.")
    args = parser.parse_args()

    csv_file = None
    csv_writer = None
    if args.csv:
        csv_file = open(args.csv, "w", newline="")
        csv_writer = csv.writer(csv_file)
        csv_writer.writerow([
            "frame", "time_s", "rms", "spectral_flux", "spectral_centroid", "zcr",
            "z_rms", "z_flux", "z_centroid_delta", "z_zcr",
            "anomaly_score", "is_anomaly",
        ])

    if sys.platform == "win32":
        os.system("")

    extractor = FeatureExtractor(SAMPLE_RATE)
    detector = AnomalyDetector()
    source = DesktopAudioSource(sample_rate=SAMPLE_RATE, chunk_size=HOP_SIZE)

    frame_buffer = np.zeros(FRAME_SIZE, dtype=np.float32)

    print_header()
    for _ in range(DISPLAY_LINES):
        print()

    frame_count = 0
    anomaly_count = 0
    start_time = time.time()

    try:
        with source:
            while True:
                chunk = source.read_chunk(timeout=5.0)

                frame_buffer[:FRAME_SIZE - HOP_SIZE] = frame_buffer[HOP_SIZE:]
                frame_buffer[FRAME_SIZE - HOP_SIZE:] = chunk

                frame_count += 1
                if frame_count < 2:
                    extractor.extract(frame_buffer)
                    continue

                features = extractor.extract(frame_buffer)
                result = detector.process(features)

                if result.is_anomaly:
                    anomaly_count += 1

                elapsed = time.time() - start_time
                print_dashboard(features, result, frame_count, elapsed, anomaly_count)

                if csv_writer is not None:
                    z = result.z_scores
                    csv_writer.writerow([
                        frame_count,
                        f"{elapsed:.2f}",
                        f"{features['rms']:.6f}",
                        f"{features['spectral_flux']:.6f}",
                        f"{features['spectral_centroid']:.1f}",
                        f"{features['zcr']:.6f}",
                        f"{z.get('rms', 0):.4f}",
                        f"{z.get('spectral_flux', 0):.4f}",
                        f"{z.get('centroid_delta', 0):.4f}",
                        f"{z.get('zcr', 0):.4f}",
                        f"{result.score:.4f}",
                        "1" if result.is_anomaly else "0",
                    ])

    except KeyboardInterrupt:
        elapsed = time.time() - start_time
        mins, secs = divmod(int(elapsed), 60)
        print(f"\n  {BOLD}Stopped.{RESET}")
        print(f"  Frames: {frame_count}  |  Duration: {mins:02d}:{secs:02d}  |  Anomalies detected: {anomaly_count}")
    finally:
        if csv_file is not None:
            csv_file.close()
            print(f"  Features logged to: {args.csv}")


if __name__ == "__main__":
    main()
