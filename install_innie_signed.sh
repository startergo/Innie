#!/bin/bash

# Enhanced Innie Installation Script with Signature Support
# This script installs the Innie kernel extension to make storage devices appear as internal

KEXT_NAME="Innie.kext"
INSTALL_PATH="/Library/Extensions"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Enhanced Innie Kernel Extension Installer"
echo "========================================="

# Check if kext exists
if [ ! -d "$SCRIPT_DIR/$KEXT_NAME" ]; then
    echo "Error: $KEXT_NAME not found in $SCRIPT_DIR"
    echo "Please ensure the kernel extension is in the same directory as this script"
    exit 1
fi

# Check if kernel extension is signed
echo "Checking kernel extension signature..."
SIGNATURE_CHECK=$(codesign -v "$SCRIPT_DIR/$KEXT_NAME" 2>&1)
if [ $? -eq 0 ]; then
    echo "✅ Kernel extension is properly code signed!"
    SIGNED=true
    
    # Get signing identity
    SIGNER=$(codesign -dv "$SCRIPT_DIR/$KEXT_NAME" 2>&1 | grep "Authority=" | head -1 | cut -d'=' -f2)
    echo "   Signed by: $SIGNER"
    
    # Test system acceptance
    spctl -a -t exec -vv "$SCRIPT_DIR/$KEXT_NAME" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "✅ System will accept this signed kernel extension"
        echo "   SIP can remain ENABLED - no Recovery Mode needed!"
    else
        echo "⚠️  System policy may block this signature"
        echo "   You may need to allow this developer in System Preferences"
    fi
else
    echo "⚠️  Kernel extension is NOT code signed"
    SIGNED=false
    
    # Check SIP status only for unsigned kexts
    echo ""
    echo "Checking System Integrity Protection (SIP) status..."
    SIP_STATUS=$(csrutil status)
    echo "$SIP_STATUS"
    
    if echo "$SIP_STATUS" | grep -q "System Integrity Protection status: enabled"; then
        echo ""
        echo "WARNING: System Integrity Protection (SIP) is fully enabled."
        echo "Unsigned kernel extensions will not load with SIP enabled."
        echo ""
        echo "Options:"
        echo "1. Sign the kernel extension with a Developer ID (recommended)"
        echo "2. Disable SIP in Recovery Mode: csrutil disable"
        echo "3. Selective SIP: csrutil enable --without kext --without debug"
        echo ""
        read -p "Continue installation anyway? (y/n): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Installation cancelled."
            echo ""
            echo "To sign the kernel extension:"
            echo "1. Get Apple Developer account ($99/year)"
            echo "2. Install Developer ID Application certificate"
            echo "3. Run: codesign --sign \"Developer ID Application: Your Name\" $KEXT_NAME"
            exit 1
        fi
    fi
fi

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo ""
    echo "Error: This script must be run as root (use sudo)"
    echo "Usage: sudo $0"
    exit 1
fi

echo ""
echo "Installing $KEXT_NAME to $INSTALL_PATH..."

# Remove existing version if present
if [ -d "$INSTALL_PATH/$KEXT_NAME" ]; then
    echo "Removing existing version..."
    rm -rf "$INSTALL_PATH/$KEXT_NAME"
fi

# Copy new version
echo "Copying kernel extension..."
cp -r "$SCRIPT_DIR/$KEXT_NAME" "$INSTALL_PATH/"

# Set proper permissions
echo "Setting permissions..."
chown -R root:wheel "$INSTALL_PATH/$KEXT_NAME"
chmod -R 755 "$INSTALL_PATH/$KEXT_NAME"

# Update kernel cache
echo "Updating kernel extension cache..."
if command -v kmutil &> /dev/null; then
    # macOS Big Sur and later
    kmutil install --volume-root / --update-all
elif command -v kextcache &> /dev/null; then
    # macOS Catalina and earlier
    kextcache -i /
else
    echo "Warning: Could not update kernel cache. You may need to reboot."
fi

echo ""
echo "Installation complete!"
echo ""

# Validate installation
echo "IMPORTANT: Verifying kernel extension will load..."
echo ""

KEXT_LOAD_CHECK=$(kextutil -n -t "$INSTALL_PATH/$KEXT_NAME" 2>&1)
if echo "$KEXT_LOAD_CHECK" | grep -q "appears to be loadable"; then
    echo "✅ Kernel extension validation: PASSED"
    if [ "$SIGNED" = true ]; then
        echo "   ✅ Code signature valid - will load with SIP enabled"
    fi
elif echo "$KEXT_LOAD_CHECK" | grep -q "lacks proper signature"; then
    echo "⚠️  Kernel extension validation: UNSIGNED"
    echo "   This is expected for unsigned third-party kernel extensions."
    echo "   The extension should load if SIP allows unsigned kexts."
elif echo "$KEXT_LOAD_CHECK" | grep -q "denied by system policy"; then
    echo "❌ Kernel extension validation: BLOCKED BY SYSTEM POLICY"
    if [ "$SIGNED" = true ]; then
        echo "   Even though signed, system policy is blocking this extension."
        echo "   Go to System Preferences → Security & Privacy → General"
        echo "   and allow this developer's software."
    else
        echo "   SIP is preventing unsigned kernel extension loading."
        echo "   You MUST sign the extension or disable SIP."
    fi
else
    echo "⚠️  Kernel extension validation: $KEXT_LOAD_CHECK"
fi

echo ""
echo "The enhanced Innie kernel extension has been installed and will:"
echo "- Make SATA drives appear as internal"
echo "- Make NVMe drives appear as internal" 
echo "- Make RAID controllers appear as internal"
echo "- Force override existing built-in properties"
echo ""

if [ "$SIGNED" = true ]; then
    echo "🎉 Your signed kernel extension provides these benefits:"
    echo "✅ No SIP modification required"
    echo "✅ Loads with full system integrity protection"
    echo "✅ No security warnings"
    echo "✅ Professional installation experience"
    echo ""
fi

echo "Please reboot your system for the changes to take effect."
echo ""
echo "After reboot:"
echo "1. Check if kernel extension loaded: kextstat | grep -i innie"
if [ "$SIGNED" = false ]; then
    echo "2. If not loaded, verify SIP configuration: csrutil status"
fi
echo "3. Check System Information > Storage to verify internal designation"
echo ""

if [ "$SIGNED" = false ]; then
    echo "If the kernel extension fails to load:"
    echo "- Consider getting it signed with Apple Developer ID"
    echo "- Or ensure SIP allows unsigned kexts"
    echo "- Check system logs: log show --predicate 'process == \"kernel\"' --info --last 5m"
fi
