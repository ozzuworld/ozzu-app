# GitHub Actions iOS Build Fix

## Issue

After downgrading `livekit_client` to 2.3.6 and `protobuf` to 3.1.0 for Dart SDK 3.5.0 compatibility, the GitHub Actions iOS build fails with:

```
error: Module 'audio_session' not found
```

This happens because GitHub Actions has cached the old pod dependencies.

## Root Cause

The GitHub Actions workflow is caching:
- iOS CocoaPods (`ios/Pods/`)
- Podfile.lock
- DerivedData

When dependencies are downgraded, these caches become stale and contain references to the old versions.

## Solutions

### Solution 1: Invalidate GitHub Actions Cache (Recommended)

**Option A: Clear cache via GitHub UI**
1. Go to your repository on GitHub
2. Click "Actions" tab
3. Click "Caches" in the left sidebar
4. Delete all caches related to iOS builds
   - Look for caches with keys like: `pods-`, `ios-`, `cocoapods-`

**Option B: Modify cache key in workflow**

In your GitHub Actions workflow file (`.github/workflows/*.yml`), update the cache key to force a rebuild:

```yaml
# Before
- uses: actions/cache@v3
  with:
    path: ios/Pods
    key: ${{ runner.os }}-pods-${{ hashFiles('ios/Podfile.lock') }}

# After (add version suffix to force new cache)
- uses: actions/cache@v3
  with:
    path: ios/Pods
    key: ${{ runner.os }}-pods-v2-${{ hashFiles('ios/Podfile.lock') }}
    #                            ^^^^ Change this version number
```

### Solution 2: Update GitHub Actions Workflow

Add explicit pod cleaning steps before building:

```yaml
- name: Clean iOS Pods
  run: |
    cd ios
    rm -rf Pods Podfile.lock
    cd ..

- name: Flutter Dependencies
  run: flutter pub get

- name: Install Pods
  run: |
    cd ios
    pod install --repo-update
    cd ..

- name: Build iOS
  run: flutter build ios --release --no-codesign
```

### Solution 3: Use the Clean Build Script

The repository now includes `ios_clean_build.sh`. Update your workflow to use it:

```yaml
- name: Clean iOS Build
  run: ./ios_clean_build.sh

- name: Build iOS
  run: flutter build ios --release --no-codesign
```

### Solution 4: Disable Pod Caching Temporarily

Comment out or temporarily disable the pod caching step in your workflow:

```yaml
# - uses: actions/cache@v3
#   with:
#     path: ios/Pods
#     key: ${{ runner.os }}-pods-${{ hashFiles('ios/Podfile.lock') }}
```

After one successful build, you can re-enable it with an updated cache key.

## Complete Example Workflow

Here's a complete example of a GitHub Actions workflow that handles iOS builds correctly:

```yaml
name: iOS Build

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  build-ios:
    runs-on: macos-latest

    steps:
    - uses: actions/checkout@v3

    - name: Setup Flutter
      uses: subosito/flutter-action@v2
      with:
        flutter-version: '3.35.7'  # Match your Flutter version
        channel: 'stable'

    - name: Flutter Doctor
      run: flutter doctor -v

    # Clean old pods (important after dependency changes)
    - name: Clean iOS Pods
      run: |
        cd ios
        rm -rf Pods Podfile.lock .symlinks
        cd ..

    - name: Flutter Clean
      run: flutter clean

    - name: Flutter Pub Get
      run: flutter pub get

    # Updated cache key (v2) to invalidate old cache
    - name: Cache Pods
      uses: actions/cache@v3
      with:
        path: ios/Pods
        key: ${{ runner.os }}-pods-v2-${{ hashFiles('**/Podfile.lock') }}
        restore-keys: |
          ${{ runner.os }}-pods-v2-

    - name: Install CocoaPods
      run: |
        cd ios
        pod install --repo-update
        cd ..

    - name: Build iOS (No Code Sign)
      run: flutter build ios --release --no-codesign

    # Or build IPA
    # - name: Build IPA
    #   run: flutter build ipa --release
```

## Key Changes to Make

1. **Update cache key version** - Change from `v1` to `v2` (or remove version and add it)
2. **Add explicit pod cleaning** - Remove `Pods/` and `Podfile.lock` before build
3. **Use `--repo-update`** - Ensures CocoaPods fetches latest pod specs
4. **Run `flutter clean`** - Clears Flutter build cache

## Testing the Fix

After making changes:

1. **Trigger a new workflow run**
   - Make a small commit and push
   - Or manually trigger the workflow if possible

2. **Monitor the build logs**
   - Check that pods are being installed fresh
   - Look for "Installing audio_session" in pod install output
   - Verify build succeeds without module errors

3. **Verify cache is working**
   - Subsequent builds should be faster (using cache)
   - But first build after cache invalidation will be slower

## Why This Specific Error?

The `audio_session` module is a dependency of:
- `livekit_client` (your video/audio SDK)
- `just_audio` (your audio player)

When you downgraded `livekit_client` from 2.4.8 to 2.3.6:
- The required `audio_session` version changed
- Old cached pods still referenced the old version
- Xcode couldn't find the module in the new location

## Prevention

To prevent this in the future:

1. **Version cache keys** - Always use versioned cache keys
2. **Document dependency changes** - Note when major downgrades/upgrades happen
3. **Clean builds after dependency changes** - Add clean steps to workflow
4. **Use cache restore-keys carefully** - Don't fall back to very old caches

## Additional Resources

- [GitHub Actions Cache Documentation](https://docs.github.com/en/actions/using-workflows/caching-dependencies-to-speed-up-workflows)
- [Flutter CI/CD Best Practices](https://docs.flutter.dev/deployment/cd)
- [CocoaPods Documentation](https://guides.cocoapods.org/)

## Still Having Issues?

If the build still fails after trying these solutions:

1. **Check DerivedData cache** - Some workflows also cache Xcode DerivedData
2. **Update CocoaPods version** - Ensure workflow uses recent CocoaPods: `gem install cocoapods`
3. **Check Xcode version** - Verify GitHub Actions is using compatible Xcode version
4. **Run locally** - Try building on a local macOS to isolate CI-specific issues

---

**Last Updated:** 2025-11-18
**Related to:** Dart SDK 3.5.0 compatibility, dependency downgrades
