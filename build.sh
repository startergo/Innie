#!/bin/bash

# Enhanced Innie Kernel Extension Build Script
# Builds, signs (if possible), and packages the Enhanced Innie kernel extension
# Usage: ./build.sh [clean|build|package|help] [DEBUG|RELEASE]

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
KEXT_NAME="Innie.kext"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
PACKAGE_DIR="${PROJECT_DIR}/Enhanced-Innie-Package"
ENTITLEMENTS="${PROJECT_DIR}/Innie.entitlements"

# Build configuration
ARCH="x86_64"
MAC_KERNEL_SDK="${PROJECT_DIR}/MacKernelSDK"
SDK_PATH="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"

echo -e "${BLUE}=== Enhanced Innie Build Script ===${NC}"
echo -e "${BLUE}Project Directory: ${PROJECT_DIR}${NC}"
echo -e "${BLUE}Architecture: ${ARCH}${NC}"
echo -e "${BLUE}Using MacKernelSDK: ${MAC_KERNEL_SDK}${NC}"

# Function to print status
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if build environment is ready
check_build_environment() {
    print_status "Checking build environment..."
    
    # Check for MacKernelSDK submodule
    if [ ! -d "$MAC_KERNEL_SDK" ] || [ ! -f "$MAC_KERNEL_SDK/Headers/Availability.h" ]; then
        print_warning "MacKernelSDK not found or incomplete"
        
        # Check if we're in a git repository
        if [ ! -d ".git" ]; then
            print_error "Not in a git repository - cannot initialize MacKernelSDK submodule"
            print_error "Please manually download MacKernelSDK to: $MAC_KERNEL_SDK"
            print_error "Download from: https://github.com/acidanthera/MacKernelSDK"
            exit 1
        fi
        
        print_status "Initializing MacKernelSDK submodule..."
        if git submodule update --init --recursive MacKernelSDK; then
            print_status "✅ MacKernelSDK submodule initialized successfully"
        else
            print_error "❌ Failed to initialize MacKernelSDK submodule"
            print_error "Please manually run: git submodule update --init --recursive MacKernelSDK"
            exit 1
        fi
    fi
    
    # Verify MacKernelSDK is properly set up
    if [ ! -f "$MAC_KERNEL_SDK/Headers/Availability.h" ]; then
        print_error "MacKernelSDK appears incomplete - missing Headers/Availability.h"
        print_error "Try running: git submodule update --init --recursive"
        exit 1
    fi
    
    if [ ! -f "$MAC_KERNEL_SDK/Library/$ARCH/libkmod.a" ]; then
        print_error "MacKernelSDK missing libkmod.a for architecture: $ARCH"
        exit 1
    fi
    
    print_status "✅ MacKernelSDK found and appears complete"
    
    # Check for Xcode command line tools
    if ! xcode-select -p &>/dev/null; then
        print_error "Xcode command line tools not found. Please install with: xcode-select --install"
        exit 1
    fi
    
    print_status "✅ Xcode command line tools found"
    
    # Try to find the macOS SDK (fallback)
    if [ ! -d "$SDK_PATH" ]; then
        print_warning "Standard macOS SDK not found at expected location."
        SDK_PATH="$(xcrun --show-sdk-path)"
        if [ -d "$SDK_PATH" ]; then
            print_status "Using SDK at: $SDK_PATH"
        else
            print_warning "No macOS SDK found - build may use MacKernelSDK only"
        fi
    fi
}

# Function to clean build directory
clean_build() {
    print_status "Cleaning build directory..."
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
}

# Function to build kernel extension
build_kext() {
    print_status "Building Enhanced Innie kernel extension with MacKernelSDK ($BUILD_CONFIG configuration)..."
    
    cd "$PROJECT_DIR"
    
    # Compile the kernel extension using MacKernelSDK
    xcodebuild \
        -project Innie.xcodeproj \
        -target Innie \
        -configuration "$BUILD_CONFIG" \
        -arch "$ARCH" \
        CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
        KERNEL_EXTENSION_HEADER_SEARCH_PATHS="$MAC_KERNEL_SDK/Headers" \
        KERNEL_FRAMEWORK_HEADERS="$MAC_KERNEL_SDK/Headers" \
        LIBRARY_SEARCH_PATHS="$MAC_KERNEL_SDK/Library/$ARCH" \
        MACOSX_DEPLOYMENT_TARGET=10.9 \
        CODE_SIGNING_ALLOWED=NO \
        clean build
    
    if [ $? -eq 0 ]; then
        print_status "Build completed successfully with MacKernelSDK!"
        
        # Verify the built kext
        if [ -d "$BUILD_DIR/$KEXT_NAME" ]; then
            print_status "✅ Kernel extension created: $BUILD_DIR/$KEXT_NAME"
            
            # Show some info about the built kext
            KEXT_SIZE=$(du -sh "$BUILD_DIR/$KEXT_NAME" | cut -f1)
            print_status "   Size: $KEXT_SIZE"
            
            # Check if it has the right architecture
            if file "$BUILD_DIR/$KEXT_NAME/Contents/MacOS/Innie" | grep -q "$ARCH"; then
                print_status "✅ Correct architecture: $ARCH"
            else
                print_warning "Architecture verification failed"
            fi
        else
            print_error "Kernel extension not found after build"
            exit 1
        fi
    else
        print_error "Build failed!"
        exit 1
    fi
}

# Function to check for signing certificates
check_certificates() {
    print_status "Checking for code signing certificates..."
    
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -n1 | cut -d'"' -f2)
    
    if [ -z "$SIGNING_IDENTITY" ]; then
        print_warning "No valid Developer ID Application certificate found."
        print_warning "Kernel extension will remain unsigned."
        return 1
    else
        print_status "Found signing identity: $SIGNING_IDENTITY"
        return 0
    fi
}

# Function to sign kernel extension
sign_kext() {
    if check_certificates; then
        print_status "Signing kernel extension..."
        
        codesign -f -s "$SIGNING_IDENTITY" --entitlements "$ENTITLEMENTS" "$BUILD_DIR/$KEXT_NAME"
        
        if [ $? -eq 0 ]; then
            print_status "Signing completed successfully!"
            
            # Verify signature
            print_status "Verifying signature..."
            codesign -vvv "$BUILD_DIR/$KEXT_NAME"
            
            return 0
        else
            print_error "Signing failed!"
            return 1
        fi
    else
        print_warning "Skipping signing - no valid certificate available"
        return 1
    fi
}

# Function to create installation package
create_package() {
    print_status "Creating installation package..."
    
    rm -rf "$PACKAGE_DIR"
    mkdir -p "$PACKAGE_DIR"
    
    # Copy kernel extension
    cp -R "$BUILD_DIR/$KEXT_NAME" "$PACKAGE_DIR/"
    
    # Copy installation scripts
    cp "$PROJECT_DIR/install_innie.sh" "$PACKAGE_DIR/" 2>/dev/null || true
    cp "$PROJECT_DIR/install_innie_signed.sh" "$PACKAGE_DIR/" 2>/dev/null || true
    
    # Create README
    cat > "$PACKAGE_DIR/README.md" << 'EOF'
# Enhanced Innie Kernel Extension

## What it does
Makes all storage devices (SATA, NVMe, RAID controllers) appear as "Internal" in macOS System Information, perfect for professional hackintosh setups.

## Enhanced Features
- ✅ Comprehensive RAID controller support (LSI, Adaptec, HighPoint, ATTO, Promise, Areca)
- ✅ Force property override for stubborn devices
- ✅ Automatic timeout handling for proper initialization
- ✅ Enhanced logging for troubleshooting
- ✅ Multiple update passes for maximum compatibility

## Installation

### Method 1: Automated Installation
```bash
sudo ./install_innie.sh
```

### Method 2: Manual Installation
1. Disable SIP (System Integrity Protection) if using unsigned version:
   - Reboot to Recovery Mode (Cmd+R)
   - Open Terminal and run: `csrutil disable`
   - Reboot normally

2. Install the kernel extension:
   ```bash
   sudo cp -R Innie.kext /Library/Extensions/
   sudo chown -R root:wheel /Library/Extensions/Innie.kext
   sudo chmod -R 755 /Library/Extensions/Innie.kext
   sudo kextcache -i /
   ```

3. Reboot your system

## Verification
After installation and reboot:
1. Open "System Information" (About This Mac → System Report)
2. Go to Hardware → Storage
3. All your drives should now show "Physical Interconnect Location: Internal"

## Supported RAID Controllers
- LSI MegaRAID (all variants)
- Adaptec RAID controllers  
- HighPoint RocketRAID series
- ATTO ExpressSAS/ThunderLink
- Promise SuperTrak series
- Areca ARC series
- Intel RAID controllers
- AMD RAID controllers

## Troubleshooting
- Check system logs: `sudo dmesg | grep Innie`
- Verify SIP status: `csrutil status`
- Rebuild kernel cache: `sudo kextcache -i /`

Built with Enhanced Innie Build Script
EOF

    # Make install scripts executable
    chmod +x "$PACKAGE_DIR"/*.sh 2>/dev/null || true
    
    print_status "Package created at: $PACKAGE_DIR"
}

# Function to create distributable archive
create_archive() {
    print_status "Creating distributable archive..."
    
    cd "$PROJECT_DIR"
    local config_suffix
    if [[ "$BUILD_CONFIG" == "Debug" ]]; then
        config_suffix="-DEBUG"
    else
        config_suffix=""
    fi
    ARCHIVE_NAME="Enhanced-Innie$(config_suffix)-$(date +%Y%m%d-%H%M%S).tar.gz"
    
    tar -czf "$ARCHIVE_NAME" -C "Enhanced-Innie-Package" .
    
    print_status "Archive created: $ARCHIVE_NAME"
    print_status "Size: $(du -h "$ARCHIVE_NAME" | cut -f1)"
}

# Function to show build summary
show_summary() {
    echo
    echo -e "${BLUE}=== Build Summary ===${NC}"
    print_status "Configuration: $BUILD_CONFIG"
    
    if [ -f "$BUILD_DIR/$KEXT_NAME" ]; then
        print_status "✅ Kernel extension built successfully"
        print_status "   Location: $BUILD_DIR/$KEXT_NAME"
        
        # Show debug logging status
        if [[ "$BUILD_CONFIG" == "Debug" ]]; then
            print_status "🐛 Debug logging: ENABLED (check Console.app or dmesg for 'Innie:' messages)"
        else
            print_status "🔧 Debug logging: DISABLED (optimized release build)"
        fi
        
        # Check if signed
        if codesign -v "$BUILD_DIR/$KEXT_NAME" &>/dev/null; then
            print_status "✅ Kernel extension is signed"
        else
            print_warning "⚠️  Kernel extension is unsigned (requires SIP configuration)"
        fi
    fi
    
    if [ -d "$PACKAGE_DIR" ]; then
        print_status "✅ Installation package created"
        print_status "   Location: $PACKAGE_DIR"
    fi
    
    if ls Enhanced-Innie-*.tar.gz &>/dev/null; then
        print_status "✅ Distributable archive created"
        print_status "   Files: $(ls Enhanced-Innie-*.tar.gz)"
    fi
    
    echo
    print_status "Next steps:"
    echo "  1. Copy Enhanced-Innie-Package to your hackintosh system"
    echo "  2. Run: sudo ./install_innie.sh"
    echo "  3. Reboot and check System Information"
}

# Main build process
main() {
    check_build_environment
    clean_build
    build_kext
    sign_kext  # This will gracefully handle missing certificates
    create_package
    create_archive
    show_summary
}

# Handle command line arguments
parse_arguments() {
    local command="${1:-}"
    local config="${2:-}"
    local detected_config=""
    
    # Parse configuration argument (can be first or second argument)
    for arg in "$1" "$2"; do
        case "$arg" in
            "DEBUG"|"debug")
                detected_config="Debug"
                ;;
            "RELEASE"|"release"|"Release")
                detected_config="Release"
                ;;
        esac
    done
    
    # Parse command argument
    case "$command" in
        "clean")
            if [[ "$config" =~ ^(DEBUG|debug|RELEASE|release|Release)$ ]]; then
                command="clean"
            fi
            ;;
        "build-only")
            if [[ "$config" =~ ^(DEBUG|debug|RELEASE|release|Release)$ ]]; then
                command="build-only"
            fi
            ;;
        "package-only")
            if [[ "$config" =~ ^(DEBUG|debug|RELEASE|release|Release)$ ]]; then
                command="package-only"
            fi
            ;;
        "DEBUG"|"debug"|"RELEASE"|"release"|"Release")
            # Configuration specified as first argument, default to full build
            command=""
            ;;
    esac
    
    echo "$command|$detected_config"
}

# Parse arguments first to set BUILD_CONFIG
RESULT=$(parse_arguments "$@")
COMMAND=$(echo "$RESULT" | cut -d'|' -f1)
DETECTED_CONFIG=$(echo "$RESULT" | cut -d'|' -f2)

# Set BUILD_CONFIG from detected config or default
if [[ -n "$DETECTED_CONFIG" ]]; then
    BUILD_CONFIG="$DETECTED_CONFIG"
else
    BUILD_CONFIG="Release"
fi

case "$COMMAND" in
    "clean")
        print_status "Cleaning build artifacts..."
        rm -rf "$BUILD_DIR"
        rm -rf "$PACKAGE_DIR"
        rm -f Enhanced-Innie-*.tar.gz
        print_status "Clean completed!"
        ;;
    "build-only")
        print_status "Building in $BUILD_CONFIG configuration..."
        check_build_environment
        clean_build
        build_kext
        ;;
    "package-only")
        create_package
        create_archive
        ;;
    "help"|"-h"|"--help")
        echo "Enhanced Innie Build Script"
        echo
        echo "Usage: $0 [command] [configuration]"
        echo "   or: $0 [configuration] [command]"
        echo
        echo "Commands:"
        echo "  (none)      - Full build, sign, and package"
        echo "  clean       - Clean all build artifacts"
        echo "  build-only  - Build kernel extension only"
        echo "  package-only- Create package and archive only"
        echo "  help        - Show this help message"
        echo
        echo "Configurations:"
        echo "  DEBUG       - Build with debug symbols and logging"
        echo "  RELEASE     - Build optimized release version (default)"
        echo
        echo "Examples:"
        echo "  $0                    # Build release version"
        echo "  $0 DEBUG             # Build debug version"
        echo "  $0 build-only DEBUG  # Build debug version only"
        echo "  $0 DEBUG clean       # Clean build artifacts"
        ;;
    *)
        print_status "Building in $BUILD_CONFIG configuration..."
        main
        ;;
esac
