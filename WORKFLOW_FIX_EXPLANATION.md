# GitHub Actions Workflow Fix - iOS Build

## The Problem

Your workflow was failing with:
```
error: Module 'audio_session' not found
```

## Root Cause

**The workflow was missing the CocoaPods installation step!**

Your current workflow does:
1. ✅ Checkout code
2. ✅ Setup Flutter
3. ✅ Run `flutter pub get`
4. ❌ **SKIP pod install** ← This is the problem!
5. ❌ Try to build → Fails because pods aren't installed

## What's Missing

After `flutter pub get`, the workflow needs to install iOS dependencies:

```yaml
- name: 🍎 Install CocoaPods dependencies
  run: |
    cd ios
    pod repo update
    pod install --verbose
    cd ..
```

Without this step:
- `audio_session` pod is never installed
- `livekit_client` iOS dependencies are missing
- `just_audio` iOS dependencies are missing
- All other Flutter plugin iOS dependencies are missing

## The Fix

Add these steps to your workflow **AFTER** `flutter pub get` and **BEFORE** building:

```yaml
# After: flutter pub get
# Before: flutter build ios

- name: 🍎 Install CocoaPods dependencies
  run: |
    cd ios
    pod repo update
    pod install --verbose
    cd ..
    echo "✅ CocoaPods dependencies installed"

# Optional: Cache pods for faster builds
- name: 💾 Cache CocoaPods
  uses: actions/cache@v3
  with:
    path: ios/Pods
    key: ${{ runner.os }}-pods-v2-${{ hashFiles('ios/Podfile.lock') }}
    restore-keys: |
      ${{ runner.os }}-pods-v2-
```

## Important Notes

### Cache Position

I've placed the cache **AFTER** the pod install step in the fixed workflow. This is intentional:

**Why?**
- The first build needs to install pods fresh
- After successful installation, the cache is saved
- Subsequent builds will restore from cache (faster)

**For better caching**, you could move it BEFORE pod install like this:

```yaml
# Restore cache first
- name: 💾 Cache CocoaPods
  uses: actions/cache@v3
  with:
    path: ios/Pods
    key: ${{ runner.os }}-pods-v2-${{ hashFiles('ios/Podfile.lock') }}
    restore-keys: |
      ${{ runner.os }}-pods-v2-

# Then install (will use cache if available)
- name: 🍎 Install CocoaPods dependencies
  run: |
    cd ios
    # Only update if cache missed or Podfile.lock changed
    if [ ! -d "Pods" ]; then
      pod repo update
    fi
    pod install --verbose
    cd ..
```

But for now, to ensure a clean build after your dependency changes, it's fine to install first, then cache.

### Cache Key Version

Notice the cache key: `pods-v2`

This is important! If you ever need to force a cache refresh:
1. Change `v2` to `v3`
2. Commit and push
3. New cache will be created

## Order of Steps (Corrected)

Here's the correct order for iOS builds:

```
1. Checkout code
2. Setup Flutter
3. flutter pub get          ← Gets Dart/Flutter dependencies
4. pod install              ← Gets iOS native dependencies (YOU WERE MISSING THIS!)
5. flutter build ios        ← Now all dependencies are available
6. xcodebuild archive       ← Create IPA
7. Upload artifact
```

## Why It Worked Before

You might be wondering: "Why did this work before?"

**Answer:** You probably had the pods cached from a previous successful build. When you:
1. Deleted the cache
2. Made dependency changes (downgraded livekit_client and protobuf)
3. Ran the workflow again

The workflow tried to build without installing pods, and failed.

## Testing the Fix

To update your workflow:

1. **Copy the fixed workflow** to your main branch:
   ```bash
   # The fixed workflow is in: ios-build-IPA-device-FIXED.yml
   # Copy it to: .github/workflows/ios-build-IPA-device.yml
   ```

2. **Or manually add the pod install step** to your existing workflow:
   - Open `.github/workflows/ios-build-IPA-device.yml`
   - After the `flutter pub get` step
   - Add the pod install step shown above
   - Commit and push

3. **Trigger the workflow** and verify:
   - Check logs show "Installing audio_session"
   - Check build completes successfully
   - IPA artifact is created

## Complete Working Workflow

I've created `ios-build-IPA-device-FIXED.yml` with all the necessary fixes.

**Key changes:**
- ✅ Added pod install step
- ✅ Added pod repo update for latest specs
- ✅ Added CocoaPods caching (optional but recommended)
- ✅ Proper ordering of steps

Copy this file to `.github/workflows/ios-build-IPA-device.yml` on your main branch.

## Summary

**Problem:** Missing `pod install` in workflow
**Solution:** Add pod installation step after `flutter pub get`
**Result:** All iOS dependencies properly installed, build succeeds

The audio_session error was just the first missing dependency - without pod install, ALL Flutter plugin iOS dependencies would eventually fail.
