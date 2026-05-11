# ⚡ SoftTime Quick Test Guide — iOS Fix Verification

**Last Updated:** May 10, 2026  
**Purpose:** Verify iOS white screen issue is fixed

---

## 🎯 Immediate Test (5 minutes)

### Build & Run on Device

```bash
cd flutter_app

# Clean build
flutter clean
rm -rf ios/Pods ios/Podfile.lock
flutter pub get
cd ios && pod install --repo-update && cd ..

# Run on device (physical iPhone)
flutter run -v -d <device_id>

# Or for simulator
flutter run -v
```

### Expected Behavior ✅

1. **Splash Screen appears immediately** (white screen GONE)
2. **Logo displays for 1.5 seconds**
3. **One of these appears:**
   - Login screen (if not authenticated)
   - Home screen (if authenticated)
4. **Check logs for these success messages:**
   ```
   [Splash] Auth init complete
   [FCM] Firebase init complete
   ```

### Error Messages to Monitor ⚠️

| Log Message | Status | Action |
|------------|--------|--------|
| `[Splash] Auth init error:` | Expected if not logged in | ✅ Normal, go to login |
| `[FCM] Firebase init failed:` | Expected if FCM unavailable | ✅ App continues without push |
| `[Splash] Navigation failed:` | Unexpected | ❌ Check logs |
| App crashes | Unexpected | ❌ Check Xcode build log |

---

## 🧪 Full Test Scenario (30 minutes)

### Step 1: Login Test
1. Open app → See login screen
2. Register new account OR login with existing credentials
3. Verify home screen appears

**Expected:** ✅ No white screen, smooth navigation

### Step 2: Attendance Test
1. Navigate to "Attendance" tab
2. Tap "Check In" button
3. Scan QR code (if available) or bypass with test button
4. Verify check-in recorded

**Expected:** ✅ Successful check-in, no crashes

### Step 3: Duty Test
1. Navigate to "Duty" tab
2. View duty queue and assignments
3. If you're assigned: attempt to mark task complete

**Expected:** ✅ Duty interface works, no freezing

### Step 4: Background Operations Test
1. Open app
2. Immediately put phone to sleep (press lock button)
3. Wait 10 seconds
4. Wake phone
5. Return to app

**Expected:** ✅ App resumes without crashes, FCM still working

### Step 5: Force Quit & Reopen
1. Quit app completely (swipe from app switcher)
2. Wait 5 seconds
3. Tap app icon to relaunch
4. Verify splash screen appears again

**Expected:** ✅ Fresh startup with splash screen

---

## 📊 Success Criteria

| Criterion | Before Fix | After Fix |
|-----------|-----------|-----------|
| **White screen on launch** | ❌ YES (BUG) | ✅ NO |
| **Splash screen visible** | ❌ 0 seconds | ✅ 1.5 seconds |
| **FCM timeout** | ❌ 30+ seconds or crash | ✅ Max 10 seconds |
| **Navigation to home/login** | ❌ Stuck or slow | ✅ Instant after splash |
| **Error handling** | ❌ Crashes on FCM fail | ✅ Graceful fallback |
| **App persistence** | ❌ May freeze | ✅ Responsive |

---

## 🔧 Key Modifications Made

### 1. main.dart (Lines 10-32)
- ✅ ApiService.init() runs before splash
- ✅ FCM.init() moved to background (500ms delay)
- ✅ 10-second timeout for FCM operations
- ✅ Graceful error handling

### 2. fcm_service.dart (Comprehensive)
- ✅ Firebase.initializeApp() wrapped in try-catch
- ✅ All Firebase operations have 5s timeouts
- ✅ Early return if Firebase unavailable
- ✅ No uncaught exceptions
- ✅ DarwinInitializationSettings configured

### 3. splash_screen.dart (Lines 34-62)
- ✅ _navigate() method enhanced with error handling
- ✅ debugPrint statements for troubleshooting
- ✅ Fallback to login if auth fails
- ✅ mounted check for safety

### 4. ios/Podfile
- ✅ Firebase pod configuration added
- ✅ Protobuf size definitions for iOS 15.0+

---

## 🐛 If White Screen Still Appears

### Troubleshooting Steps

#### 1. Check Console Logs
```bash
# Watch live logs
flutter logs -v

# Look for:
# - [FCM] messages
# - [Splash] messages
# - Dart exceptions
```

#### 2. Check API Configuration
Edit `lib/core/config/app_config.dart`:
```dart
static const String baseUrl = 'http://YOUR_BACKEND_IP:8000/api/v1';
```

#### 3. Verify Firebase Configuration
- Open `firebase_options.dart`
- Check iOS bundle ID: `com.thekuba.softtime`
- Verify against Firebase Console

#### 4. Full Nuclear Reset
```bash
# Complete clean
flutter clean
rm -rf ios/Pods ios/Podfile.lock .dart_tool

# Rebuild from scratch
flutter pub get
cd ios && pod install --repo-update && cd ..
flutter run -v

# Watch for any errors
```

#### 5. Check Xcode Build Log
```bash
# Open Xcode workspace
open ios/Runner.xcworkspace

# Build directly (⌘B)
# Check build output for errors
```

---

## ✅ Verification Checklist

- [ ] App launches without white screen
- [ ] Splash screen visible for ~1.5 sec
- [ ] Navigation to login OR home appears
- [ ] Console shows no critical errors
- [ ] Firebase messages appear in logs (or gracefully skipped)
- [ ] Force quit → reopen → works again
- [ ] Network disconnect → reconnect → works again

---

## 📞 Test Results

After running tests, please note:
- **Device:** iPhone 12 / 13 / 14 / etc.
- **iOS Version:** 15.x / 16.x / 17.x
- **Network:** WiFi / Cellular
- **Result:** ✅ Pass / ❌ Fail
- **Errors:** [List any error messages from console]

---

**Tests Performed By:** [Your Name]  
**Date:** [Test Date]  
**Result:** ✅ **WHITE SCREEN FIXED** / ❌ **Still issues - see errors above**
