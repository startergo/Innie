#!/bin/bash

# Enhanced Innie Installation Script
# This script installs the Innie kernel extension to make storage devices appear as internal

KEXT_NAME="Innie.kext"
INSTALL_PATH="/Library/Extensions"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Enhanced Innie Kernel Extension Installer"
echo "========================================="

# Check SIP status
echo "Checking System Integrity Protection (SIP) status..."
SIP_STATUS=$(csrutil status)
echo "$SIP_STATUS"

if echo "$SIP_STATUS" | grep -q "System Integrity Protection status: enabled"; then
    echo ""
    echo "WARNING: System Integrity Protection (SIP) is fully enabled."
    echo "Kernel extensions may not load properly with SIP enabled."
    echo ""
    echo "To disable SIP:"
    echo "1. Reboot and hold Command+R to enter Recovery Mode"
    echo "2. Open Terminal from Utilities menu"
    echo "3. Run: csrutil disable"
    echo "4. Reboot normally"
    echo ""
    echo "Alternatively, for selective SIP configuration:"
    echo "csrutil enable --without kext --without debug"
    echo ""
    read -p "Continue installation anyway? (y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 1
    fi
fi

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)"
    echo "Usage: sudo $0"
    exit 1
fi

# Check if kext exists
if [ ! -d "$SCRIPT_DIR/$KEXT_NAME" ]; then
    echo "Error: $KEXT_NAME not found in $SCRIPT_DIR"
    echo "Please ensure the kernel extension is in the same directory as this script"
    exit 1
fi

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
echo "IMPORTANT: Verifying kernel extension will load..."
echo ""

# Check if kext can be loaded
KEXT_LOAD_CHECK=$(kextutil -n -t "$INSTALL_PATH/$KEXT_NAME" 2>&1)
if echo "$KEXT_LOAD_CHECK" | grep -q "appears to be loadable"; then
    echo "✅ Kernel extension validation: PASSED"
elif echo "$KEXT_LOAD_CHECK" | grep -q "lacks proper signature"; then
    echo "⚠️  Kernel extension validation: SIGNATURE WARNING"
    echo "   This is expected for unsigned third-party kernel extensions."
    echo "   The extension should still load if SIP allows unsigned kexts."
elif echo "$KEXT_LOAD_CHECK" | grep -q "denied by system policy"; then
    echo "❌ Kernel extension validation: BLOCKED BY SYSTEM POLICY"
    echo "   SIP is preventing kernel extension loading."
    echo "   You MUST disable SIP or configure it to allow kernel extensions."
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
echo "Please reboot your system for the changes to take effect."
echo ""
echo "After reboot:"
echo "1. Check if kernel extension loaded: kextstat | grep -i innie"
echo "2. If not loaded, verify SIP configuration: csrutil status"
echo "3. Check System Information > Storage to verify internal designation"
echo ""
echo "If the kernel extension fails to load:"
echo "- Ensure SIP is disabled or configured to allow unsigned kexts"
echo "- Check system logs: log show --predicate 'process == \"kernel\"' --info --last 5m"
