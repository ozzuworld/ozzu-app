#!/bin/bash

# iOS Clean Build Script for CI/CD
# This script ensures a clean iOS build after dependency changes

set -e  # Exit on error

echo "🧹 Starting iOS clean build process..."

# Step 1: Clean iOS specific directories
echo "📦 Cleaning iOS pods and cache..."
if [ -d "ios/Pods" ]; then
    rm -rf ios/Pods
    echo "  ✓ Removed Pods directory"
fi

if [ -f "ios/Podfile.lock" ]; then
    rm -f ios/Podfile.lock
    echo "  ✓ Removed Podfile.lock"
fi

if [ -d "ios/.symlinks" ]; then
    rm -rf ios/.symlinks
    echo "  ✓ Removed .symlinks"
fi

if [ -d "ios/Flutter/Flutter.framework" ]; then
    rm -rf ios/Flutter/Flutter.framework
    echo "  ✓ Removed Flutter.framework"
fi

if [ -f "ios/Flutter/Flutter.podspec" ]; then
    rm -f ios/Flutter/Flutter.podspec
    echo "  ✓ Removed Flutter.podspec"
fi

# Step 2: Clean Flutter build cache
echo ""
echo "🧼 Cleaning Flutter build cache..."
flutter clean
echo "  ✓ Flutter clean completed"

# Step 3: Get Flutter dependencies
echo ""
echo "📥 Getting Flutter dependencies..."
flutter pub get
echo "  ✓ Flutter pub get completed"

# Step 4: Install CocoaPods dependencies
echo ""
echo "🍎 Installing CocoaPods dependencies..."
cd ios

# Check if pod command exists
if ! command -v pod &> /dev/null; then
    echo "❌ Error: CocoaPods is not installed"
    echo "   Please install CocoaPods: sudo gem install cocoapods"
    exit 1
fi

# Install pods with repo update
pod install --repo-update
echo "  ✓ Pod install completed"

cd ..

echo ""
echo "✅ iOS clean build setup completed successfully!"
echo ""
echo "You can now run:"
echo "  flutter build ios --release"
echo "  or"
echo "  flutter build ipa"
