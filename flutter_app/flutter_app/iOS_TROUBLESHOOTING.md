# 🔧 SoftTime Flutter App — iOS Troubleshooting Guide

**Problem:** White screen on iPhone when opening the app  
**Last Updated:** May 10, 2026

---

## 🎯 What Was Fixed

### Main Issues Addressed

1. **Firebase Initialization Hanging**
   - Firebase + FCM initialization now runs in background (delayed start)
   - Does NOT block app startup if Firebase is unavailable
   - 10-second timeout for FCM operations

2. **API Service Initialization**
   - Separated from main/FCM init
   - Runs before app display
   - Includes secure storage setup (Keychain on iOS)

3. **SplashScreen Navigation**
   - Better error handling with try-catch blocks
   - Fallback to login if auth init fails
   - 10-second timeout for auth check

4. **iOS Podfile Configuration**
   - Fixed x86_64 architecture issues on Apple Silicon simulators
   - Added Firebase-specific build settings

---

## 🚀 Quick Start to Fix White Screen

### Step 1: Clean Build

```bash
cd flutter_app

# Clean everything
flutter clean
rm -rf ios/Pods ios/Podfile.lock ios/.symlinks
rm -rf build/

# Get fresh dependencies
flutter pub get
cd ios && pod repo update && pod install && cd ..
```

### Step 2: Build & Run

**For Device:**
```bash
flutter run -v
```

**For Simulator:**
```bash
flutter run -v --target lib/main.dart
```

### Step 3: Check Logs

```bash
# Watch device logs in real-time
flutter logs -v

# Or via Xcode:
# Window > Devices and Simulators > Select device > View logs
```

---

## 🔍 Debugging White Screen

### Check These Logs

```
[Splash] Auth init error
[FCM] Firebase init failed
[FCM] Token update failed
[API] Base URL not set
```

### Common Causes & Fixes

| Issue | Symptom | Fix |
|-------|---------|-----|
| Firebase missing | `[FCM] Firebase init failed` | Check `firebase_options.dart` has correct config |
| API unreachable | `[API] Connection timeout` | Verify backend URL in `/core/config/app_config.dart` |
| Network issue | Stuck on splash 10+ sec | Check WiFi/cellular, ping backend |
| Secure storage fail | `[API] Storage read error` | Clear app data: Settings > SoftTime > Offload App |
| Pods not updated | Build errors | Run `pod repo update && pod install` |

---

## 📱 Step-by-Step Startup Flow

```
1. main() starts
   ↓
2. Flutter bindings initialized
   ↓
3. Locale formatting loaded (ru)
   ↓
4. ApiService.init() → Secure storage + Dio setup
   ↓
5. SplashScreen displayed (animation 1.5 sec)
   ↓
6. Parallel:
   a) FcmService.init() (background, timeout 10 sec)
   b) AuthProvider.init() (auth check, timeout 10 sec)
   ↓
7. Navigation:
   ✅ Authenticated → /home
   ❌ Not auth → /login
   ⚠️ Error → /login (fallback)
```

---

## 🔑 API Configuration

Check [lib/core/config/app_config.dart](lib/core/config/app_config.dart):

```dart
class AppConfig {
  static const String baseUrl = 'http://your-backend-ip:8000/api/v1';
  // Change to your backend URL
}
```

**For Testing:**
```dart
static const String baseUrl = 'http://192.168.1.100:8000/api/v1'; // Your machine IP
```

---

## 🔐 Firebase Setup

### If FCM Token Not Updating

1. Check `firebase_options.dart` has valid credentials
2. Verify iOS bundle ID matches Firebase project:
   - Firebase Console → Project Settings → iOS app
   - Check `com.thekuba.softtime` matches Xcode Bundle ID

3. Force token update:
   - `Settings > SoftTime > Notifications` → Toggle off/on
   - Or in app: Logout → Login again

### Download Firebase Config Again

1. Go to https://console.firebase.google.com
2. Select project → Project Settings → iOS app
3. Download `GoogleService-Info.plist`
4. Drag to Xcode (check "Copy items" + "Add to targets")

---

## 📋 iOS Build Checklist

- [ ] `pod install` completed without errors
- [ ] Minimum iOS deployment target: 15.0 (Podfile, Xcode)
- [ ] Firebase `GoogleService-Info.plist` added to Xcode
- [ ] `Build Phases > Copy Bundle Resources` includes plist
- [ ] Signing team set correctly
- [ ] No missing frameworks (check Xcode build log)
- [ ] Pod dependencies resolved (no conflicts)

---

## 🧪 Test Steps

### 1. Check API Connection
```dart
// In terminal while app loads:
curl -v http://your-backend:8000/api/v1/health
```

### 2. Test Firebase
```dart
// Add to main.dart main() after Firebase init:
final token = await FirebaseMessaging.instance.getToken();
print('FCM Token: $token');
```

### 3. Enable Verbose Logging
```bash
flutter run -v 2>&1 | tee flutter_run.log
```

---

## 🆘 If Still White Screen

### Nuclear Option: Complete Reset

```bash
# On device/simulator
Settings > General > Storage > SoftTime > Offload App → Delete
Settings > General > Storage > SoftTime > Delete App

# In project
flutter clean
rm -rf ios/Pods ios/Podfile.lock 
rm -rf flutter_app/.dart_tool

# Rebuild
flutter pub get
cd ios && pod install --repo-update && cd ..
flutter run -v
```

### Check Xcode Build Log
```bash
# Open Xcode
open ios/Runner.xcworkspace

# Build & watch full console output
⌘ + B (Build)
⌘ + ⇧ + Y (Show build log)
```

---

## 📞 Support

- **Logs Location:** Xcode > Window > Devices and Simulators
- **Flutter Doctor:** `flutter doctor -v`
- **Pod Diagnostic:** `pod install --repo-update` then check for errors
- **API Health:** `curl -v http://backend:8000/docs` (should return Swagger UI)

---

## Version Info

| Component | Version |
|-----------|---------|
| Flutter | Latest stable (3.x+) |
| iOS | 15.0+ |
| Firebase Core | 2.x+ |
| Firebase Messaging | 14.x+ |
| Riverpod | 2.x |

---

**Last working fix:** May 10, 2026 - FCM background init + splash error handling
