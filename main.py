"""
Night Watch — Kivy App Entry Point (Phase 5)

Minimal app that starts/stops the monitoring foreground service and
shows basic status.  The full UI (timeline, event detail, playback)
is built in Phase 6.
"""

import os
import sys
import time
from datetime import datetime

from kivy.app import App
from kivy.clock import Clock
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.label import Label
from kivy.uix.button import Button
from kivy.core.window import Window
from kivy.utils import platform

# Add app root to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from night_watch.database import NightWatchDB
from night_watch.config import get_data_dir


class NightWatchApp(App):
    """Minimal Night Watch app for Phase 5."""

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.monitoring = False
        self.service = None
        self.db = None
        self.session_start = None

    def build(self):
        Window.clearcolor = (0.08, 0.08, 0.12, 1)

        self.root = BoxLayout(orientation="vertical", padding=40, spacing=20)

        # Title
        self.title_label = Label(
            text="🌙 NIGHT WATCH",
            font_size="32sp",
            size_hint_y=0.15,
            color=(0.9, 0.9, 1, 1),
            bold=True,
        )
        self.root.add_widget(self.title_label)

        # Status
        self.status_label = Label(
            text="Ready",
            font_size="24sp",
            size_hint_y=0.1,
            color=(0.5, 0.8, 0.5, 1),
        )
        self.root.add_widget(self.status_label)

        # Time display
        self.time_label = Label(
            text="",
            font_size="48sp",
            size_hint_y=0.2,
            color=(0.7, 0.7, 0.8, 1),
        )
        self.root.add_widget(self.time_label)

        # Event counter
        self.event_label = Label(
            text="Events tonight: 0",
            font_size="20sp",
            size_hint_y=0.1,
            color=(0.6, 0.6, 0.7, 1),
        )
        self.root.add_widget(self.event_label)

        # Spacer
        self.root.add_widget(Label(size_hint_y=0.2))

        # Start/Stop button
        self.toggle_btn = Button(
            text="START MONITORING",
            font_size="20sp",
            size_hint=(0.6, 0.12),
            pos_hint={"center_x": 0.5},
            background_color=(0.2, 0.6, 0.3, 1),
            color=(1, 1, 1, 1),
            bold=True,
        )
        self.toggle_btn.bind(on_press=self.toggle_monitoring)
        self.root.add_widget(self.toggle_btn)

        # Spacer
        self.root.add_widget(Label(size_hint_y=0.13))

        # Update clock
        Clock.schedule_interval(self.update_display, 1.0)

        return self.root

    def on_start(self):
        """Request permissions on Android."""
        if platform == "android":
            from android.permissions import request_permissions, Permission
            request_permissions([
                Permission.RECORD_AUDIO,
                Permission.FOREGROUND_SERVICE,
            ])

    def toggle_monitoring(self, instance):
        if self.monitoring:
            self.stop_monitoring()
        else:
            self.start_monitoring()

    def start_monitoring(self):
        self.monitoring = True
        self.session_start = time.time()
        self.toggle_btn.text = "STOP"
        self.toggle_btn.background_color = (0.7, 0.2, 0.2, 1)
        self.status_label.text = "● Monitoring"
        self.status_label.color = (0.3, 0.9, 0.3, 1)

        if platform == "android":
            from jnius import autoclass
            PythonActivity = autoclass("org.kivy.android.PythonActivity")
            service = autoclass("org.kivy.android.PythonService")
            service.start(
                PythonActivity.mActivity,
                "Night Watch Service",
            )
            self.service = service

        # Open DB for reading events
        data_dir = get_data_dir()
        db_path = os.path.join(data_dir, "night_watch.db")
        self.db = NightWatchDB(db_path)

    def stop_monitoring(self):
        self.monitoring = False
        self.toggle_btn.text = "START MONITORING"
        self.toggle_btn.background_color = (0.2, 0.6, 0.3, 1)
        self.status_label.text = "Stopped"
        self.status_label.color = (0.8, 0.5, 0.5, 1)

        if platform == "android" and self.service is not None:
            from jnius import autoclass
            PythonActivity = autoclass("org.kivy.android.PythonActivity")
            service = autoclass("org.kivy.android.PythonService")
            service.stop(PythonActivity.mActivity)
            self.service = None

        if self.db is not None:
            self.db.close()
            self.db = None

    def update_display(self, dt):
        """Update the time and event count every second."""
        now = datetime.now()
        self.time_label.text = now.strftime("%I:%M %p")

        if self.monitoring and self.db is not None:
            try:
                sessions = self.db.get_all_sessions()
                if sessions:
                    latest = sessions[0]
                    events = self.db.get_session_events(latest["id"])
                    self.event_label.text = f"Events tonight: {len(events)}"
            except Exception:
                pass


if __name__ == "__main__":
    NightWatchApp().run()
