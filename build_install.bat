@echo off
set PATH=D:\flutter\flutter\bin;C:\Windows\System32;C:\Windows\System32\WindowsPowerShell\v1.0;C:\Program Files\Git\mingw64\bin;C:\Program Files\Git\cmd;C:\Users\DALI\AppData\Local\Android\Sdk\platform-tools;%PATH%
cd /d D:\mob\SalaryApp
echo Stopping existing Gradle daemons...
call .\android\gradlew.bat --stop 2>nul
echo Building SalaryApp CA debug...
flutter build apk --flavor ca -t lib/main.dart --debug --no-pub --quiet
if %ERRORLEVEL% neq 0 (
  echo BUILD FAILED with code %ERRORLEVEL%
  exit /b %ERRORLEVEL%
)
echo Installing on device...
adb install -r build\app\outputs\flutter-apk\app-ca-debug.apk
echo DONE
