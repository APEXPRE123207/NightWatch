#!/usr/bin/env python3
"""
Night Watch — Phase 1: Live Feature Monitor (Desktop)

Captures microphone audio in real time, extracts acoustic features per frame,
and displays them as a continuously updating console dashboard.

Goal: visually confirm that the four features (RMS, spectral flux, spectral
centroid, ZCR) actually separate steady background noise (fan, AC) from
transient events (talking, movement, impacts).

Usage
-----
    python phase1_live.py               # plain console bars
    python phase1_live.py --csv out.csv  # also log features to CSV for review

Press Ctrl+C to stop.
"""

import argparse
import csv
import os
import sys
import time

import numpy as np

# Ensure the package is importable when running from the project root
sys.path.insert(0, os.path.dirname(__file__))

from night_watch.config import (
    SAMPLE_RATE,
    HOP_SIZE,
    FRAME_SIZE,
    DISPLAY_RMS_MAX,
    DISPLAY_FLUX_MAX,
    DISPLAY_CENTROID_MAX,
    DISPLAY_ZCR_MAX,
)
from night_watch.feature_extractor import FeatureExtractor
from night_watch.audio_source import DesktopAudioSource


# ── Display helpers ─────────────────────────────────────────────────────────────

BAR_WIDTH = 30

# ANSI colour codes (Windows 10+ Terminal supports these)
RESET = "\033[0m"
DIM = "\033[2m"
BOLD = "\033[1m"
GREEN = "\033[92m"
YELLOW = "\033[93m"
RED = "\033[91m"
CYAN = "\033[96m"
MAGENTA = "\033[95m"


def _bar(value: float, max_val: float, width: int = BAR_WIDTH) -> str:
    """Render a coloured horizontal bar."""
    ratio = max(0.0, min(1.0, value / max_val))
    filled = int(ratio * width)

    if ratio < 0.33:
        colour = GREEN
    elif ratio < 0.66:
        colour = YELLOW
    else:
        colour = RED

    return colour + "█" * filled + DIM + "░" * (width - filled) + RESET


def _clear_lines(n: int) -> None:
    """Move the cursor up n lines and clear them (ANSI)."""
    for _ in range(n):
        sys.stdout.write("\033[A\033[2K")


def print_header() -> None:
    """Print the static dashboard header once."""
    print()
    print(f"{BOLD}  ╔══════════════════════════════════════════════════════════╗{RESET}")
    print(f"{BOLD}  ║   🌙  NIGHT WATCH — Phase 1: Live Feature Monitor      ║{RESET}")
    print(f"{BOLD}  ╚══════════════════════════════════════════════════════════╝{RESET}")
    print()
    print(f"  {DIM}Sample rate: {SAMPLE_RATE} Hz  |  Frame: {FRAME_SIZE} samples  |  Hop: {HOP_SIZE} samples{RESET}")
    print(f"  {DIM}Press Ctrl+C to stop{RESET}")
    print()


DISPLAY_LINES = 7  # number of lines the feature block occupies (including blanks)


def print_features(features: dict, frame_count: int, elapsed: float) -> None:
    """Overwrite the feature display block in place."""
    if frame_count > 1:
        _clear_lines(DISPLAY_LINES)

    rms = features["rms"]
    flux = features["spectral_flux"]
    centroid = features["spectral_centroid"]
    zcr = features["zcr"]

    mins, secs = divmod(int(elapsed), 60)

    print(f"  {CYAN}RMS Energy   {RESET} {rms:8.5f}  {_bar(rms, DISPLAY_RMS_MAX)}")
    print(f"  {MAGENTA}Spec. Flux   {RESET} {flux:8.5f}  {_bar(flux, DISPLAY_FLUX_MAX)}")
    print(f"  {YELLOW}Centroid     {RESET} {centroid:7.0f} Hz {_bar(centroid, DISPLAY_CENTROID_MAX)}")
    print(f"  {GREEN}ZCR          {RESET} {zcr:8.5f}  {_bar(zcr, DISPLAY_ZCR_MAX)}")
    print()
    print(f"  {DIM}Frame: {frame_count}  |  Elapsed: {mins:02d}:{secs:02d}{RESET}")
    print()


# ── Main loop ───────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="Night Watch Phase 1 — live feature monitor")
    parser.add_argument(
        "--csv",
        type=str,
        default=None,
        help="Path to a CSV file for logging feature values each frame.",
    )
    args = parser.parse_args()

    # Optional CSV logger
    csv_file = None
    csv_writer = None
    if args.csv:
        csv_file = open(args.csv, "w", newline="")
        csv_writer = csv.writer(csv_file)
        csv_writer.writerow(["frame", "time_s", "rms", "spectral_flux", "spectral_centroid", "zcr"])

    # Enable ANSI escape sequences on Windows
    if sys.platform == "win32":
        os.system("")  # triggers VT100 mode in Windows Terminal

    extractor = FeatureExtractor(SAMPLE_RATE)
    source = DesktopAudioSource(sample_rate=SAMPLE_RATE, chunk_size=HOP_SIZE)

    # Audio frame buffer: holds FRAME_SIZE samples, shifts by HOP_SIZE each step
    frame_buffer = np.zeros(FRAME_SIZE, dtype=np.float32)

    print_header()
    # Print blank lines that will be overwritten on the first update
    for _ in range(DISPLAY_LINES):
        print()

    frame_count = 0
    start_time = time.time()

    try:
        with source:
            while True:
                chunk = source.read_chunk(timeout=5.0)

                # Shift the frame buffer left by one hop and append the new chunk
                frame_buffer[:FRAME_SIZE - HOP_SIZE] = frame_buffer[HOP_SIZE:]
                frame_buffer[FRAME_SIZE - HOP_SIZE:] = chunk

                frame_count += 1

                # Skip the very first frame (buffer is half zeros)
                if frame_count < 2:
                    # Still need to call extract so prev_spectrum is initialised
                    extractor.extract(frame_buffer)
                    continue

                features = extractor.extract(frame_buffer)
                elapsed = time.time() - start_time

                print_features(features, frame_count, elapsed)

                if csv_writer is not None:
                    csv_writer.writerow([
                        frame_count,
                        f"{elapsed:.2f}",
                        f"{features['rms']:.6f}",
                        f"{features['spectral_flux']:.6f}",
                        f"{features['spectral_centroid']:.1f}",
                        f"{features['zcr']:.6f}",
                    ])

    except KeyboardInterrupt:
        print(f"\n  {BOLD}Stopped.{RESET}  Captured {frame_count} frames.")
    finally:
        if csv_file is not None:
            csv_file.close()
            print(f"  Features logged to: {args.csv}")


if __name__ == "__main__":
    main()
