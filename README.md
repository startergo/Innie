Enhanced Innie
==============

An enhanced kernel extension for making all PCIe drives (including RAID controllers) appear as internal in macOS System Information.

## Enhanced Features

- ✅ **Comprehensive RAID Support**: LSI, Adaptec, HighPoint, ATTO, Promise, Areca controllers
- ✅ **Force Property Override**: For stubborn devices that resist standard methods  
- ✅ **Automatic Detection**: Scans all PCIe storage controllers
- ✅ **Enhanced Logging**: Detailed debug information for troubleshooting
- ✅ **Multiple Update Passes**: Ensures maximum compatibility
- ✅ **Timeout Handling**: Proper initialization timing

## Build System

This project includes a complete build system with automated scripts:

### Quick Start
```bash
# From the Innie/Innie directory:
./build.sh              # Full build, sign, and package
make                     # Alternative build method
make help               # See all available targets
```

### Build Script Options
```bash
./build.sh              # Full build and package
./build.sh build-only   # Build kernel extension only  
./build.sh clean        # Clean all build artifacts
./build.sh help         # Show help information
```

### Makefile Targets
```bash
make build              # Build kernel extension
make sign               # Build and sign (if certificates available)
make package            # Create installation package
make install            # Install system-wide (requires sudo)
make clean              # Clean build artifacts
make archive            # Create distributable archive
```

## Installation

### Automated Installation
```bash
sudo ./install_innie.sh
```

### Manual Installation
1. Disable SIP if using unsigned version:
   ```bash
   # In Recovery Mode:
   csrutil disable
   ```

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
3. All drives should show "Physical Interconnect Location: Internal"

## Supported RAID Controllers

- **LSI MegaRAID** (all variants)
- **Adaptec RAID** controllers
- **HighPoint RocketRAID** series
- **ATTO ExpressSAS/ThunderLink**
- **Promise SuperTrak** series
- **Areca ARC** series
- **Intel RAID** controllers
- **AMD RAID** controllers

## Alternative: OpenCore Method

An alternative to Innie is to add the `built-in` device property for each drive using [OpenCore](https://github.com/acidanthera/OpenCorePkg). However, this Enhanced Innie version provides automatic detection and works with complex RAID setups that may be difficult to configure manually.

## Dependencies

- **MacKernelSDK**: Included as submodule for kernel development
- **Xcode Command Line Tools**: For compilation (`xcode-select --install`)

## Troubleshooting

- Check system logs: `sudo dmesg | grep Innie`
- Verify SIP status: `csrutil status`
- Rebuild kernel cache: `sudo kextcache -i /`
- Check installation: `kextstat | grep Innie`
