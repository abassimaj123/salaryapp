#!/bin/bash
export PATH="/d/flutter/flutter/bin:/c/Windows/System32:/c/Windows/SysWOW64:/c/Program Files/Git/mingw64/bin:/c/Program Files/Git/cmd:/c/Users/DALI/AppData/Local/Android/Sdk/platform-tools:$PATH"
cd /d/mob/SalaryApp
flutter build apk --flavor ca -t lib/main.dart --debug 2>&1 && \
adb install -r build/app/outputs/flutter-apk/app-ca-debug.apk 2>&1
