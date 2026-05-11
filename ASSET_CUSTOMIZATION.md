# SalaryApp - Asset Customization Guide

## Overview
SalaryApp now has 3 distinct flavors (CA, US, UK) with theme-specific colors and branding.

## Theme Colors

### 🇨🇦 Canada (app_theme_ca.dart)
- **Primary**: #0066CC (Professional Blue)
- **Secondary**: #6B7280 (Slate Gray)
- **Background**: #F8FAFC
- **Dark Mode**: #1F2937

### 🇺🇸 USA (app_theme_us.dart)
- **Primary**: #DC2626 (Confident Red)
- **Secondary**: #1F2937 (Dark Gray)
- **Background**: #FFFFFF (Pure White)
- **Dark Mode**: #111827

### 🇬🇧 UK (app_theme_uk.dart)
- **Primary**: #1F2937 (Premium Black)
- **Accent**: #D4AF37 (Gold)
- **Background**: #F3F4F6
- **Dark Mode**: #0F172A

## Customization Tasks

### 1. App Icons (Launcher Icons)
**Location**: `android/app/src/{ca,us,uk}/res/mipmap-*/`

**Action Required**:
- Run: `flutter pub get`
- Generate icons: `flutter_launcher_icons`
- Or manually:
  1. Design 3 icon variants (one per theme color)
  2. Use [makeappicon.com](https://makeappicon.com) or similar
  3. Place in `android/app/src/{ca,us,uk}/res/mipmap-{hdpi,mdpi,xhdpi,xxhdpi,xxxhdpi}/`

**Naming Convention**:
```
android/app/src/ca/res/mipmap-xxxhdpi/ic_launcher.png  (CA blue icon)
android/app/src/us/res/mipmap-xxxhdpi/ic_launcher.png  (US red icon)
android/app/src/uk/res/mipmap-xxxhdpi/ic_launcher.png  (UK black icon)
```

### 2. Splash Screens (Native)
**Location**: `android/app/src/main/res/drawable/`

**Action Required**:
- Uncomment flavor-specific splash configs in `pubspec.yaml`
- Create splash images: `assets/splash/splash_{ca,us,uk}.png`
- Run: `dart run flutter_native_splash:create`

### 3. App Store Assets
- **App Name**: Salary Calculator (same for all)
- **Short Description**: Include market (e.g., "Salary Calculator (Canada)")
- **Screenshots**: Customize per market if needed

## Build & Deploy by Flavor

### Build Release APK
```bash
# Canada
flutter build apk --release --flavor ca -o build/ca.apk

# USA
flutter build apk --release --flavor us -o build/us.apk

# UK
flutter build apk --release --flavor uk -o build/uk.apk
```

### Build AAB (for Google Play)
```bash
flutter build appbundle --release --flavor ca
flutter build appbundle --release --flavor us
flutter build appbundle --release --flavor uk
```

### Install to Device
```bash
adb install -r build/ca.apk
adb install -r build/us.apk
adb install -r build/uk.apk
```

## Localization

- **CA**: English + French (fr_CA)
- **US**: English + Spanish (es_US)
- **UK**: English only

Strings are in `lib/l10n/strings_{en,es,fr}.dart`

## Key Files Modified

1. **lib/core/theme/**
   - `app_theme_base.dart` - Shared utilities
   - `app_theme_ca.dart` - Canada specific
   - `app_theme_us.dart` - USA specific
   - `app_theme_uk.dart` - UK specific

2. **lib/main.dart**
   - Updated to load theme based on `FlavorConfig`

3. **pubspec.yaml**
   - Updated `flutter_native_splash` config

## Testing

```bash
# Test Canada flavor
flutter run --flavor ca -t lib/main.dart

# Test dark mode
# Go to Settings > Display > Dark Theme

# Test alternate language
# Canada: System language = French (CA)
# USA: System language = Spanish
```

## Delivery Checklist

- [ ] App icons generated for all 3 flavors
- [ ] Splash screens created (optional but recommended)
- [ ] Tested on device in light & dark mode
- [ ] Verified theme colors load correctly per flavor
- [ ] Alternate language works (CA=French, US=Spanish)
- [ ] Built and tested all 3 APKs
- [ ] Signed APKs for app store submission
