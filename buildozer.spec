[app]

# (str) Title of your application
title = Night Watch

# (str) Package name
package.name = nightwatch

# (str) Package domain (needed for android/ios packaging)
package.domain = org.nightwatch

# (str) Source code where the main.py lives
source.dir = .

# (list) Source files to include (let empty to include all the files)
source.include_exts = py,png,jpg,kv,atlas,wav,db

# (list) List of directory to exclude into the source
source.exclude_dirs = tests, bin, .git, night_watch_data, .github

# (list) List of exclusions using pattern matching
source.exclude_patterns = phase*.py, requirements.txt, xtra

# (str) Application versioning (method 1)
version = 0.1.0

# (list) Application requirements
# comma separated e.g. requirements = sqlite3,kivy
requirements = python3,kivy,pyjnius,numpy,sqlite3

# (str) Supported orientation (one of landscape, sensorLandscape, portrait or all)
orientation = portrait

# (list) Permissions
android.permissions = RECORD_AUDIO, FOREGROUND_SERVICE, FOREGROUND_SERVICE_MICROPHONE, WAKE_LOCK

# (int) Target Android API, should be as high as possible.
android.api = 33

# (int) Minimum API your APK / AAB will support.
android.minapi = 26

# (int) Android NDK version to use
android.ndk = 25b

# (bool) If True, then skip trying to update the Android sdk
# This can be useful to avoid excess Internet downloads or save time
# when an update is due and you just want to test/build your package
android.skip_update = False

# (bool) If True, then automatically accept SDK license
# agreements. This is intended for automation only. If set to False,
# the default, you will be shown the license when building.
android.accept_sdk_license = True

# (str) Android entry point, default is ok for Kivy-based app
android.entrypoint = org.kivy.android.PythonActivity

# (list) List of service to declare
# Format: <service_name>:<python_file>[:foreground]
services = NightWatch:service/main.py:foreground

# (str) The Android arch to build for, choices: armeabi-v7a, arm64-v8a, x86, x86_64
android.archs = arm64-v8a

# (bool) enables Android auto backup feature (Android API >=23)
android.allow_backup = True

[buildozer]

# (int) Log level (0 = error only, 1 = info, 2 = debug (with command output))
log_level = 2

# (int) Display warning if buildozer is run as root (0 = False, 1 = True)
warn_on_root = 1
