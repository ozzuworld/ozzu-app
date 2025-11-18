#!/bin/bash

# Fix iOS Deployment Target for wireguard_flutter compatibility
# wireguard_flutter requires iOS 15.0+

set -e

echo "🔧 Fixing iOS Deployment Target to 15.0..."

# Update project.pbxproj to set IPHONEOS_DEPLOYMENT_TARGET to 15.0
if [ -f "ios/Runner.xcodeproj/project.pbxproj" ]; then
    echo "📝 Updating Runner.xcodeproj deployment target..."
    sed -i '' 's/IPHONEOS_DEPLOYMENT_TARGET = [0-9][0-9]*\.[0-9]/IPHONEOS_DEPLOYMENT_TARGET = 15.0/g' ios/Runner.xcodeproj/project.pbxproj
    echo "  ✅ Updated project.pbxproj"
else
    echo "  ⚠️  project.pbxproj not found"
fi

# Clean and reinstall pods
echo ""
echo "🧹 Cleaning iOS build..."
cd ios
rm -rf Pods Podfile.lock .symlinks
cd ..

flutter clean
flutter pub get

echo ""
echo "🍎 Installing pods with iOS 15.0..."
cd ios
pod install --repo-update
cd ..

echo ""
echo "✅ iOS deployment target updated to 15.0"
echo "📱 wireguard_flutter now compatible!"
