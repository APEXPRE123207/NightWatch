"""
Night Watch — Android Foreground Service (Phase 5)

This script runs as a separate Python process via python-for-android's
service support.  It:
  1. Acquires a partial wake lock (keeps CPU alive with screen off)
  2. Creates a persistent notification ("Night Watch is monitoring…")
  3. Runs the full detection pipeline in a loop
  4. Saves events to SQLite + .wav clips in app-private storage

The main Kivy app starts/stops this service.  Communication is through
the shared SQLite database — the app reads session/event data from it.
"""

import os
import sys
import time
import traceback

# Add the app root to the path so night_watch package is importable
app_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, app_root)

import numpy as np

from night_watch.config import (
    SAMPLE_RATE,
    HOP_SIZE,
    FRAME_SIZE,
    get_data_dir,
)
from night_watch.feature_extractor import FeatureExtractor
from night_watch.detector import AnomalyDetector
from night_watch.database import NightWatchDB
from night_watch.event_recorder import EventRecorder


def create_notification():
    """Create the foreground service notification."""
    from jnius import autoclass

    PythonService = autoclass("org.kivy.android.PythonService")
    Context = autoclass("android.content.Context")
    NotificationBuilder = autoclass("android.app.Notification$Builder")
    NotificationChannel = autoclass("android.app.NotificationChannel")
    NotificationManager = autoclass("android.app.NotificationManager")

    service = PythonService.mService
    CHANNEL_ID = "night_watch_monitoring"
    CHANNEL_NAME = "Night Watch Monitoring"

    # Create notification channel (required Android 8+)
    manager = service.getSystemService(Context.NOTIFICATION_SERVICE)
    channel = NotificationChannel(
        CHANNEL_ID,
        CHANNEL_NAME,
        NotificationManager.IMPORTANCE_LOW,  # Low = no sound, shows in bar
    )
    channel.setDescription("Night Watch is monitoring ambient sound")
    manager.createNotificationChannel(channel)

    # Build the notification
    builder = NotificationBuilder(service, CHANNEL_ID)
    builder.setContentTitle("Night Watch")
    builder.setContentText("Monitoring ambient sound…")
    builder.setSmallIcon(service.getApplicationInfo().icon)
    builder.setOngoing(True)

    notification = builder.build()

    # Start as foreground service
    service.startForeground(1, notification)

    return service


def acquire_wake_lock():
    """Acquire a partial wake lock to keep CPU running with screen off."""
    from jnius import autoclass

    Context = autoclass("android.content.Context")
    PowerManager = autoclass("android.os.PowerManager")
    PythonService = autoclass("org.kivy.android.PythonService")

    service = PythonService.mService
    pm = service.getSystemService(Context.POWER_SERVICE)
    wake_lock = pm.newWakeLock(
        PowerManager.PARTIAL_WAKE_LOCK,
        "NightWatch::MonitoringLock"
    )
    wake_lock.acquire()
    return wake_lock


def run_monitoring_loop():
    """Main monitoring loop — runs until the service is stopped."""

    # Set up data paths
    data_dir = get_data_dir()
    db_path = os.path.join(data_dir, "night_watch.db")
    db = NightWatchDB(db_path)
    session_id = db.create_session()
    clip_dir = os.path.join(data_dir, "events", str(session_id))

    # Create pipeline components
    from night_watch.audio_source import get_audio_source

    extractor = FeatureExtractor(SAMPLE_RATE)
    detector = AnomalyDetector()
    recorder = EventRecorder(db, session_id, clip_dir)
    source = get_audio_source(sample_rate=SAMPLE_RATE, chunk_size=HOP_SIZE)

    frame_buffer = np.zeros(FRAME_SIZE, dtype=np.float32)
    frame_count = 0
    start_time = time.time()

    print("[NightWatch Service] Starting monitoring loop…")

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

                # Feed the event recorder
                finished = recorder.process_chunk(chunk, result.is_anomaly, result.score)
                if finished:
                    print(f"[NightWatch Service] Event #{finished['number']} saved: "
                          f"{finished['duration']:.1f}s, peak={finished['peak_score']:.1f}")

    except Exception as e:
        print(f"[NightWatch Service] Error: {e}")
        traceback.print_exc()
    finally:
        recorder.finalize()
        elapsed = time.time() - start_time
        db.end_session(session_id, int(elapsed))
        db.close()
        print(f"[NightWatch Service] Session #{session_id} ended. "
              f"Duration: {int(elapsed)}s, Events: {recorder.event_count}")


def main():
    """Service entry point."""
    wake_lock = None
    try:
        # Set up foreground notification
        create_notification()
        print("[NightWatch Service] Foreground notification created")

        # Acquire wake lock
        wake_lock = acquire_wake_lock()
        print("[NightWatch Service] Wake lock acquired")

        # Run the monitoring loop
        run_monitoring_loop()

    except Exception as e:
        print(f"[NightWatch Service] Fatal error: {e}")
        traceback.print_exc()
    finally:
        if wake_lock is not None:
            try:
                wake_lock.release()
                print("[NightWatch Service] Wake lock released")
            except Exception:
                pass


if __name__ == "__main__":
    main()
