# SalaryApp — Release Checklist

## Pre-Build
- [ ] Replace all AdMob placeholder IDs (`XXXXXXXXXX`) with real unit IDs from AdMob console
- [ ] Set `kReleaseMode` ad IDs verified in `lib/config/ad_config.dart` and `lib/core/ads/ad_config.dart`
- [ ] Remove or guard `debugUnlockPremium()` call in production
- [ ] Verify `FlavorConfig.flavor` is set correctly for the target store variant (US/CA/UK)
- [ ] Confirm `minSdkVersion`, `targetSdkVersion`, and `versionCode`/`versionName` in `build.gradle`

## Android
- [ ] `android:allowBackup="false"` present in AndroidManifest.xml
- [ ] `android:networkSecurityConfig="@xml/network_security_config"` present
- [ ] Splash background color `#E65100` in values-v31 and values-night-v31
- [ ] ProGuard/R8 rules reviewed — no sensitive class names exposed
- [ ] Signed AAB with release keystore

## Play Store Listing
- [ ] `store/en-US/listing.txt` — title, short desc, full desc reviewed
- [ ] `store/es-US/listing.txt` — Spanish listing reviewed
- [ ] Screenshots captured (phone + 7" tablet)
- [ ] Feature graphic (1024×500) created
- [ ] Privacy policy URL set: `store/privacy/index.html` hosted and URL entered in Play Console
- [ ] Content rating questionnaire completed
- [ ] Target audience: 18+

## IAP
- [ ] Product ID `premium_lifetime` created and active in Play Console
- [ ] Tester accounts added to licence testing list

## Post-Release
- [ ] Verify ads serving in production (banner + interstitial + rewarded)
- [ ] Verify IAP purchase flow end-to-end
- [ ] Monitor Crashlytics for day-1 crashes
- [ ] Check Analytics events: calculation, paywall_shown, buy_tapped, pdf_exported
