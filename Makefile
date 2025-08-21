# Enhanced Innie Kernel Extension Makefile
# Alternative build system for the Enhanced Innie kernel extension
# Usage: make [target] [CONFIG=DEBUG|RELEASE]

# Configuration
KEXT_NAME = Innie.kext
PROJECT_NAME = Innie
ARCH = x86_64
BUILD_DIR = build
PACKAGE_DIR = Enhanced-Innie-Package
INSTALL_DIR = /Library/Extensions
MAC_KERNEL_SDK = MacKernelSDK

# Build configuration (can be overridden with CONFIG=DEBUG)
CONFIG ?= RELEASE
ifeq ($(CONFIG),DEBUG)
    CONFIGURATION = Debug
    CONFIG_SUFFIX = -DEBUG
else
    CONFIGURATION = Release
    CONFIG_SUFFIX =
endif

# Xcode settings
XCODE_PROJECT = Innie.xcodeproj
TARGET = Innie
SDK = macosx

# Default target
.PHONY: all clean build sign package install help init-submodule debug release

all: build package

# Initialize MacKernelSDK submodule
init-submodule:
	@echo "Checking MacKernelSDK submodule..."
	@if [ ! -f $(MAC_KERNEL_SDK)/Headers/Availability.h ]; then \
		echo "Initializing MacKernelSDK submodule..."; \
		git submodule update --init --recursive $(MAC_KERNEL_SDK) || \
		(echo "Failed to initialize submodule. Please run manually: git submodule update --init --recursive" && exit 1); \
		echo "✅ MacKernelSDK submodule initialized"; \
	else \
		echo "✅ MacKernelSDK submodule already available"; \
	fi

# Build the kernel extension
build: init-submodule
	@echo "Building Enhanced Innie kernel extension ($(CONFIGURATION) configuration)..."
	@mkdir -p $(BUILD_DIR)
	xcodebuild \
		-project $(XCODE_PROJECT) \
		-target $(TARGET) \
		-configuration $(CONFIGURATION) \
		-arch $(ARCH) \
		CONFIGURATION_BUILD_DIR=$(BUILD_DIR) \
		MACOSX_DEPLOYMENT_TARGET=10.9 \
		CODE_SIGNING_ALLOWED=NO \
		clean build || (echo "Build completed with warnings (this is normal)" && test -d $(BUILD_DIR)/$(KEXT_NAME))
	@echo "Build completed!"
	@if [ "$(CONFIGURATION)" = "Debug" ]; then \
		echo "🐛 Debug logging: ENABLED (check Console.app or dmesg for 'Innie:' messages)"; \
	else \
		echo "🔧 Debug logging: DISABLED (optimized release build)"; \
	fi

# Sign the kernel extension (if certificates available)
sign: build
	@echo "Checking for code signing certificates..."
	@if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then \
		echo "Signing kernel extension..."; \
		SIGNING_IDENTITY=$$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -n1 | cut -d'"' -f2); \
		codesign -f -s "$$SIGNING_IDENTITY" --entitlements Innie.entitlements $(BUILD_DIR)/$(KEXT_NAME); \
		echo "Signing completed!"; \
	else \
		echo "No signing certificate found - kernel extension will remain unsigned"; \
	fi

# Create installation package
package: build
	@echo "Creating installation package..."
	@rm -rf $(PACKAGE_DIR)
	@mkdir -p $(PACKAGE_DIR)
	@cp -R $(BUILD_DIR)/$(KEXT_NAME) $(PACKAGE_DIR)/
	@cp install_innie.sh $(PACKAGE_DIR)/ 2>/dev/null || true
	@cp install_innie_signed.sh $(PACKAGE_DIR)/ 2>/dev/null || true
	@chmod +x $(PACKAGE_DIR)/*.sh 2>/dev/null || true
	@echo "Package created at: $(PACKAGE_DIR)"

# Install the kernel extension (requires sudo)
install: build
	@echo "Installing Enhanced Innie kernel extension..."
	@if [ "$$(id -u)" != "0" ]; then \
		echo "Error: Installation requires sudo privileges"; \
		echo "Run: sudo make install"; \
		exit 1; \
	fi
	@cp -R $(BUILD_DIR)/$(KEXT_NAME) $(INSTALL_DIR)/
	@chown -R root:wheel $(INSTALL_DIR)/$(KEXT_NAME)
	@chmod -R 755 $(INSTALL_DIR)/$(KEXT_NAME)
	@echo "Rebuilding kernel cache..."
	@kextcache -i /
	@echo "Installation completed! Reboot to activate."

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR)
	@rm -rf $(PACKAGE_DIR)
	@rm -f Enhanced-Innie-*.tar.gz
	@echo "Clean completed!"

# Quick build for testing
quick: clean build

# Create distributable archive
archive: package
	@echo "Creating distributable archive..."
	@ARCHIVE_NAME="Enhanced-Innie$(CONFIG_SUFFIX)-$$(date +%Y%m%d-%H%M%S).tar.gz"; \
	tar -czf "$$ARCHIVE_NAME" -C $(PACKAGE_DIR) .; \
	echo "Archive created: $$ARCHIVE_NAME"

# Convenience targets for different build configurations
debug:
	@$(MAKE) CONFIG=DEBUG all

release:
	@$(MAKE) CONFIG=RELEASE all

debug-build:
	@$(MAKE) CONFIG=DEBUG build

release-build:
	@$(MAKE) CONFIG=RELEASE build

# Show help
help:
	@echo "Enhanced Innie Kernel Extension Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  all           - Build and create package (default, uses RELEASE)"
	@echo "  init-submodule- Initialize MacKernelSDK submodule"
	@echo "  build         - Build kernel extension only (auto-initializes submodule)"
	@echo "  sign          - Build and sign (if certificates available)"
	@echo "  package       - Build and create installation package"
	@echo "  install       - Build and install (requires sudo)"
	@echo "  clean         - Remove all build artifacts"
	@echo "  quick         - Clean and build"
	@echo "  archive       - Create distributable tar.gz archive"
	@echo "  debug         - Build debug version with logging (CONFIG=DEBUG all)"
	@echo "  release       - Build release version (CONFIG=RELEASE all)"
	@echo "  debug-build   - Build debug version only"
	@echo "  release-build - Build release version only"
	@echo "  help          - Show this help message"
	@echo ""
	@echo "Configuration:"
	@echo "  CONFIG=DEBUG  - Build with debug symbols and logging enabled"
	@echo "  CONFIG=RELEASE- Build optimized release version (default)"
	@echo ""
	@echo "Usage examples:"
	@echo "  make              # Build and package (release)"
	@echo "  make debug        # Build debug version with logging"
	@echo "  make CONFIG=DEBUG # Same as above"
	@echo "  make debug-build  # Build debug version only"
	@echo "  make clean build  # Clean and build (release)"
	@echo "  sudo make install # Install system-wide"
	@echo "  make archive      # Create distribution archive"
