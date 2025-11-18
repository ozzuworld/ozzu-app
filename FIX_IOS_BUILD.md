# Fix iOS Build Error - Module 'audio_session' not found

## The Issue

After downgrading dependencies for Dart SDK 3.5.0 compatibility, the iOS build fails with:
```
error: Module 'audio_session' not found
```

This happens because the iOS CocoaPods need to be reinstalled after dependency changes.

## Solution

Run these commands in order:

### 1. Clean iOS Build
```bash
cd ios
rm -rf Pods
rm -rf Podfile.lock
rm -rf .symlinks
rm -rf Flutter/Flutter.framework
rm -rf Flutter/Flutter.podspec
cd ..
```

### 2. Clean Flutter Build
```bash
flutter clean
```

### 3. Get Flutter Dependencies
```bash
flutter pub get
```

### 4. Reinstall iOS Pods
```bash
cd ios
pod deintegrate
pod install --repo-update
cd ..
```

### 5. Try Building Again
```bash
flutter build ios --release
```

## Alternative: One-liner Clean Script

If you're on macOS/Linux, you can run this all at once:

```bash
cd ios && rm -rf Pods Podfile.lock .symlinks Flutter/Flutter.framework Flutter/Flutter.podspec && cd .. && flutter clean && flutter pub get && cd ios && pod install --repo-update && cd ..
```

## If That Doesn't Work

If you still get the error, try:

1. **Update CocoaPods:**
   ```bash
   sudo gem install cocoapods
   pod repo update
   ```

2. **Clean Derived Data (Xcode):**
   - Open Xcode
   - Go to: Xcode → Preferences → Locations
   - Click the arrow next to Derived Data path
   - Delete the entire DerivedData folder
   - Or use command line:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/*
   ```

3. **Rebuild:**
   ```bash
   flutter clean
   flutter pub get
   cd ios
   pod install --repo-update
   cd ..
   flutter build ios --release
   ```

## Why This Happens

When Flutter dependencies are updated (especially downgrades), the iOS CocoaPods dependencies need to be regenerated. The `GeneratedPluginRegistrant.m` file tries to import modules that may have changed versions or aren't properly linked after the dependency change.

Cleaning and reinstalling ensures:
- All pods are fetched at the correct versions
- Plugin registration is regenerated
- Build cache is fresh
- Framework references are updated
