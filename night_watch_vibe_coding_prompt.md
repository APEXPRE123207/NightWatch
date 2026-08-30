# PROJECT PROMPT — "Night Watch": Sleep Acoustic Event Monitor

You are building an Android app called **Night Watch**. Read this entire spec before writing any code. Build it **phase by phase, in order**. Do not skip ahead to later phases, do not add speech recognition or ML classification early, and do not silently change the core detection approach described below. If you think a deviation is justified, stop and explain why before implementing it.

Treat each phase as a milestone: implement it, self-test it, commit it, then move to the next phase. Never deliver "everything at once."

---

## 0. What this app does (read this first)

The app listens to the room's ambient sound overnight (screen off, phone locked) and detects **when the acoustic environment changes** — not simply "when it gets loud." A running fan, AC hum, or steady snoring is *normal background noise* and should NOT be flagged. Someone talking, moving in bed, coughing, a door opening, footsteps, etc. SHOULD be flagged.

At the end of the night the user sees a timeline of short **events** (a few seconds to tens of seconds each) instead of a multi-hour audio file.

### Core principle (do not violate)
> **Never use raw average frequency (Hz) or raw volume alone as the trigger.** Hz is pitch, not loudness, and neither pitch nor loudness alone distinguishes "fan" from "person talking." Detection must be based on **deviation from a rolling acoustic baseline**, using multiple features (energy + spectral shape + spectral change over time), as detailed in Section 3.

---

## 1. Tech stack (Python-first, mandatory)

- **Language:** Python throughout — app logic, audio processing, and packaging.
- **UI/App framework:** [Kivy](https://kivy.org/) + [KivyMD](https://kivymd.readthedocs.io/) for the Android UI. Kivy apps compile to Android via `python-for-android`.
- **Packaging:** [Buildozer](https://github.com/kivy/buildozer) to produce the `.apk`/`.aab`.
- **Audio capture on device:** Use `pyjnius` to call Android's native `AudioRecord` API directly (Kivy/Android audio plugins are unreliable for continuous background mic capture). Wrap this behind a small `AudioSource` abstraction so it can be swapped for `sounddevice`/`pyaudio` when running the Phase 1 desktop prototype.
- **Signal processing:** `numpy` for RMS/FFT math. Do not pull in heavy ML/audio libraries (e.g. `librosa`, `torch`) until Phase 7, if ever — they are overkill for the core detector and hurt APK size/battery.
- **Local storage:** `sqlite3` (built into Python) for the event database. Store event audio clips as small `.wav` files on device storage, referenced by path from the DB.
- **Background execution on Android:** An Android **foreground service** (via `pyjnius`/`python-for-android` service support) with a persistent notification ("Night Watch is monitoring…"), so the OS doesn't kill the mic process when the screen is off. This is required — do not attempt to keep monitoring alive from the main Activity alone.
- **Build automation:** **GitHub Actions**, not local builds, is the primary way this app gets built into an installable APK. See Section 7 for the exact workflow. Reasoning: Buildozer's Android toolchain is Linux-specific and has a fragile local setup (SDK/NDK versions, Java version, Cython version); GitHub Actions gives a clean, reproducible Ubuntu container and produces a downloadable artifact/release APK on every push, without the developer needing a working local Android build environment.

If you (the coding agent) determine partway through that Kivy cannot satisfy a hard requirement (e.g. true background mic capture on modern Android with battery constraints), stop and flag it rather than silently switching frameworks — but attempt the above stack first, since it's the most maintainable pure-Python path.

---

## 2. High-level architecture

```
                 ┌─────────────────────┐
                 │     NIGHT MODE       │
                 │ (foreground service) │
                 └──────────┬──────────┘
                            │
                       Microphone
                            │
                            ▼
                  ┌───────────────────┐
                  │ Audio Frame        │
                  │ 0.5–2 seconds      │
                  └─────────┬─────────┘
                            │
                            ▼
                  ┌───────────────────┐
                  │ Feature Extraction │
                  │ RMS / FFT / ZCR    │
                  └─────────┬─────────┘
                            │
                 ┌──────────▼──────────┐
                 │ Rolling Baseline     │
                 └──────────┬──────────┘
                            │
                     Anomaly Score
                            │
                    ┌───────┴───────┐
                    │               │
                  Normal          Anomaly
                    │               │
                    ▼               ▼
                 Discard       Save buffer
                              (pre + post event)
                                    │
                                    ▼
                              Event Manager
                              (merge nearby events)
                                    │
                                    ▼
                             SQLite Database
                                    │
                                    ▼
                                Timeline UI
```

---

## 3. Detection algorithm (implement exactly this, then tune)

### 3.1 Framing
Process audio in overlapping frames of **1 second**, 50% overlap (0.5s hop). Sample rate 16kHz mono is sufficient — do not record at high fidelity; this isn't for audio quality, it's for detection + short playback clips.

### 3.2 Features to extract per frame (all with `numpy`)
1. **RMS energy** — overall loudness of the frame.
2. **Spectral centroid** — "center of mass" of the frequency spectrum (via FFT magnitude spectrum).
3. **Spectral flux** — L2 distance between this frame's normalized magnitude spectrum and the previous frame's. This is the single most important feature for this use case: a droning fan has near-zero flux frame-to-frame; speech, movement, and impacts spike it.
4. **Zero-crossing rate (ZCR)** — cheap extra signal, useful for distinguishing tonal hums from noisier/percussive sounds.

### 3.3 Rolling baseline
Maintain an exponentially-weighted or fixed-window rolling mean + standard deviation for each feature, computed only from frames classified as "normal" (do not let event frames pollute the baseline). Suggested: keep the last ~60 seconds of "normal" frames as the baseline window.

### 3.4 Anomaly score
For each new frame, compute a z-score-like deviation per feature against the current baseline, then combine into a single anomaly score, e.g.:

```
score = w1 * z(rms) + w2 * z(spectral_flux) + w3 * z(spectral_centroid_delta) + w4 * z(zcr)
```

Weight spectral flux most heavily (this is what separates "fan got louder" from "someone started talking"). Start with reasonable defaults (e.g. flux weight 2x the others) and make weights and the trigger threshold configurable constants, not hardcoded magic numbers buried in logic — they will need tuning against real recordings per Phase 2.

### 3.5 Event trigger
If `score > threshold` for a sustained short duration (e.g. 2 consecutive frames, to reject single-frame spikes/clicks from mic handling), mark an event start.

### 3.6 Pre-event buffer
Maintain a rolling in-memory circular buffer of the last **5 seconds** of raw audio at all times. When an event triggers, the saved clip starts from this buffer (event_start − 5s), not from the trigger moment, so the beginning of the sound isn't cut off.

### 3.7 Event end + post-buffer
End the event when the anomaly score drops back under threshold and stays there for some cooldown (e.g. 2 seconds), then append another ~3 seconds of post-event audio before closing the clip.

### 3.8 Event merging
If a new event starts within, say, 5 seconds of the previous event's end, merge them into a single event rather than creating two. This avoids fragmenting one long conversation into dozens of tiny events.

### 3.9 What NOT to do
- Do not save/keep normal (non-event) audio at all — analyze it in memory and discard it.
- Do not use a fixed 15/30-minute chunking scheme as the core loop; that concept only survives as an optional session/summary grouping in the UI layer, never as the unit of analysis or storage.

---

## 4. Data model

SQLite schema (adapt as needed, but keep this shape):

```sql
CREATE TABLE sessions (
    id INTEGER PRIMARY KEY,
    started_at TEXT,
    ended_at TEXT,
    total_monitoring_seconds INTEGER
);

CREATE TABLE events (
    id INTEGER PRIMARY KEY,
    session_id INTEGER REFERENCES sessions(id),
    start_time TEXT,
    end_time TEXT,
    duration_seconds REAL,
    peak_score REAL,
    clip_path TEXT,        -- path to the saved .wav
    event_type TEXT        -- NULL until Phase 7 classification exists
);
```

Audio clips live under app-private storage, e.g. `.../night_watch/events/<session_id>/<event_id>.wav`.

---

## 5. UI requirements (keep it simple — do not over-build this)

**Home screen** while monitoring:
```
┌──────────────────────────┐
│      NIGHT WATCH          │
│                            │
│       ● Monitoring         │
│                            │
│     11:42 PM                │
│                            │
│    Events tonight: 3       │
│                            │
│       [ STOP ]              │
└──────────────────────────┘
```

**Morning summary / timeline:**
```
Tonight
12:17 AM    8 sec
01:42 AM   14 sec
03:06 AM    5 sec
[ View Timeline ]
```

**Event detail** (tap an event): waveform preview, duration, and a `[ Play ]` button.

Do not build settings screens, accounts, cloud sync, or theming polish until the core pipeline (Phases 1–5) works and is validated. A crude functional UI is fine for early phases.

---

## 6. Build phases — implement strictly in this order

### Phase 1 — Desktop proof of concept (no Android yet)
Build a plain Python script/small app (can use `sounddevice` here, not `pyjnius`) that:
- Captures live mic audio on the desktop.
- Extracts the features from Section 3.2 per frame.
- Prints/plots RMS, spectral flux, etc. in real time.
- **Goal:** confirm the features actually separate "quiet room / fan" from "talking / movement" before any mobile work begins. Do not proceed to Phase 2 until you can show this distinction working on real test audio (record yourself: silence, fan noise, talking, tapping/knocking).

### Phase 2 — Baseline + anomaly detection
- Implement the rolling baseline (3.3) and anomaly score (3.4) on top of Phase 1.
- Test against: fan, AC, snoring-like sound, bed/sheet movement, talking, coughing, door, footsteps, and general random noise.
- Tune weights/threshold until false positives from steady background noise are rare and true positives (talking, movement, impacts) are reliably caught.
- This phase is the most important one — do not rush it.

### Phase 3 — Pre/post-event buffering and clip saving
- Add the circular in-memory buffer (3.6).
- On event trigger, assemble and write the `.wav` clip (pre-buffer + live event audio + post-buffer) to disk.
- Still desktop-only at this point is fine, but start writing to the SQLite schema from Section 4.

### Phase 4 — Event management
- Implement event start/continuation/end/merge logic (3.7, 3.8).
- Verify a single 20-second conversation produces **one** event, not five.

### Phase 5 — Port to Android + night mode
- Move audio capture to `pyjnius` + `AudioRecord`.
- Wrap the whole pipeline in an Android foreground service so it survives screen-off/locked/idle.
- Test actual overnight battery drain — this is a real engineering constraint, not an afterthought. If battery use is too high, reduce frame rate/feature cost before adding anything else.

### Phase 6 — UI
- Build the Kivy/KivyMD screens from Section 5: home/monitoring screen, nightly summary list, event detail with playback.
- Wire the UI to the SQLite data from Phases 3–4.

### Phase 7 — Optional intelligence (only after Phases 1–6 are solid)
- Optional lightweight voice-activity detection to tag events as "likely speech" vs "likely non-speech" (movement/impact/other).
- Do **not** add full transcription unless explicitly asked later — this is a roommate/shared-room environment and raises privacy considerations that should be discussed with the user before implementing, not assumed.

---

## 7. GitHub Actions — build the APK in CI (do this, don't rely on local builds)

Add `.github/workflows/build-apk.yml` that:
1. Runs on `push` to `main` and on manual `workflow_dispatch`.
2. Uses `ubuntu-latest`.
3. Sets up Python, Java (JDK 17), and the Android SDK/NDK dependencies Buildozer needs (`build-essential`, `git`, `zip`, `unzip`, `openjdk-17-jdk`, `python3-pip`, `autoconf`, `libtool`, `pkg-config`, etc. — pin exact versions once you find a working combination, since Buildozer toolchains are version-sensitive).
4. Installs `buildozer` and `cython` via pip.
5. Caches the `.buildozer` directory between runs (Android SDK/NDK downloads are large and slow) using `actions/cache`.
6. Runs `buildozer -v android debug` to produce a debug `.apk`.
7. Uploads the resulting `.apk` as a workflow artifact via `actions/upload-artifact`, and optionally attaches it to a GitHub Release on tagged commits.

Keep the workflow file itself simple and commented, so it's clear which step is doing what — this will need occasional maintenance as Android build tooling shifts.

Do not attempt to solve local Buildozer environment issues (this is a well-known pain point on macOS/Windows) — GitHub Actions' clean Ubuntu container is the intended path per Section 1.

---

## 8. Working agreement for you (the coding agent)

- Work phase by phase; after each phase, summarize what was built and what was tested before moving on.
- Keep detection thresholds/weights as named constants in one place, not scattered magic numbers.
- Prefer simple, debuggable code over cleverness — this is a personal project meant to actually get finished and run reliably overnight, not a showcase of advanced techniques.
- Flag any point where Kivy/pyjnius/Buildozer genuinely cannot do what's asked, rather than quietly working around it in a way that changes the architecture.
- Do not add cloud services, accounts, or network calls anywhere — this app should work fully offline, on-device.
