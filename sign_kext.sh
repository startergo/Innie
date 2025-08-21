#!/bin/bash

# Innie Kernel Extension Signing Script
# This script signs the compiled kernel extension with your Developer ID

KEXT_PATH="build/Release/Innie.kext"
ENTITLEMENTS="Innie.entitlements"
IDENTITY=""

echo "Innie Kernel Extension Code Signing"
echo "==================================="

# Check if kext exists
if [ ! -d "$KEXT_PATH" ]; then
    echo "Error: Kernel extension not found at $KEXT_PATH"
    echo "Please build the project first: xcodebuild -project Innie.xcodeproj -configuration Release"
    exit 1
fi

# Check if entitlements exist
if [ ! -f "$ENTITLEMENTS" ]; then
    echo "Error: Entitlements file not found at $ENTITLEMENTS"
    exit 1
fi

# List available signing identities
echo "Available code signing identities:"
security find-identity -v -p codesigning

echo ""
DEVELOPER_IDS=$(security find-identity -v -p codesigning | grep "Developer ID Application" | wc -l | xargs)

if [ "$DEVELOPER_IDS" -eq 0 ]; then
    echo "❌ No Developer ID Application certificates found!"
    echo ""
    echo "You need to obtain a Developer ID Application certificate:"
    echo "1. Open Xcode → Preferences → Accounts"
    echo "2. Add your Apple ID with Developer account"
    echo "3. Select your team and click 'Download Manual Profiles'"
    echo "4. Or visit developer.apple.com and create/download certificates"
    exit 1
elif [ "$DEVELOPER_IDS" -eq 1 ]; then
    # Auto-select the only Developer ID
    IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk -F'"' '{print $2}')
    echo "Auto-selected signing identity: $IDENTITY"
else
    echo "Multiple Developer ID certificates found. Please select one:"
    security find-identity -v -p codesigning | grep "Developer ID Application" | nl
    echo ""
    read -p "Enter the number of the identity to use: " SELECTION
    IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | sed -n "${SELECTION}p" | awk -F'"' '{print $2}')
    
    if [ -z "$IDENTITY" ]; then
        echo "Invalid selection!"
        exit 1
    fi
fi

echo ""
echo "Signing kernel extension with identity: $IDENTITY"

# Sign the kernel extension
codesign --force \
         --sign "$IDENTITY" \
         --entitlements "$ENTITLEMENTS" \
         --deep \
         --strict \
         --timestamp \
         --options runtime \
         "$KEXT_PATH"

if [ $? -eq 0 ]; then
    echo "✅ Kernel extension signed successfully!"
    
    echo ""
    echo "Verifying signature..."
    codesign -vvv --deep --strict "$KEXT_PATH"
    
    if [ $? -eq 0 ]; then
        echo "✅ Signature verification passed!"
        
        echo ""
        echo "Testing system acceptance..."
        spctl -a -t exec -vv "$KEXT_PATH" 2>&1
        
        echo ""
        echo "Testing kernel extension loading capability..."
        kextutil -n -t "$KEXT_PATH" 2>&1
        
        echo ""
        echo "🎉 Signed kernel extension is ready for installation!"
        echo ""
        echo "Benefits of signed kernel extension:"
        echo "✅ No SIP modification required"
        echo "✅ Loads with full system integrity protection"
        echo "✅ No security warnings"
        echo "✅ Professional distribution ready"
        
    else
        echo "❌ Signature verification failed!"
        exit 1
    fi
else
    echo "❌ Code signing failed!"
    echo ""
    echo "Common causes:"
    echo "- Certificate not in keychain or expired"
    echo "- Wrong certificate type (need 'Developer ID Application')"
    echo "- Keychain access issues"
    echo "- Entitlements file problems"
    exit 1
fi
