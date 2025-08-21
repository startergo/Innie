# Code Signing Guide for Innie Kernel Extension

This guide shows how to sign the Innie kernel extension with your Apple Developer account to avoid disabling SIP.

## Prerequisites

1. **Apple Developer Account** (Individual or Organization - Enterprise not required)
2. **Xcode** installed with Command Line Tools
3. **Valid Developer ID Application certificate**

## Step 1: Obtain Developer Certificates

### Method A: Through Xcode (Recommended)
1. Open **Xcode**
2. Go to **Xcode → Preferences → Accounts** (or **Xcode → Settings → Accounts** in newer versions)
3. Click the **"+"** button and **Add Apple ID**
4. Enter your Apple ID credentials that have the Developer account
5. After signing in, select your **Team** from the list
6. Click **"Manage Certificates..."**
7. Click the **"+"** button and select **"Developer ID Application"**
8. This creates and downloads the certificate you need for kernel extension signing

### Method B: Through Apple Developer Portal (Alternative)
1. Log into [developer.apple.com](https://developer.apple.com)
2. Go to **Certificates, Identifiers & Profiles**
3. Click **Certificates** → **"+"** button
4. Select **"Developer ID Application"** (under Production section)
5. Follow the prompts to create a Certificate Signing Request (CSR)
6. Upload the CSR and download the certificate
7. Double-click the downloaded certificate to install it

### Troubleshooting Certificate Setup
If you see "0 valid identities found" after setup:
- Restart Xcode and check Preferences → Accounts again
- Ensure you're signed into the correct Apple ID with Developer program
- Try logging out and back into your Apple ID in Xcode
- Check Keychain Access app - certificates should appear in "login" keychain

## Step 2: Verify Certificates

Check available signing identities:
```bash
security find-identity -v -p codesigning
```

You should see something like:
```
1) ABCDEF1234567890 "Developer ID Application: Your Name (TEAMID123)"
```

## Step 3: Sign the Kernel Extension

### Automatic Signing (Update Xcode Project)

Edit the Innie Xcode project to enable automatic signing:

1. Open `Innie.xcodeproj` in Xcode
2. Select the **Innie** target
3. In **Signing & Capabilities**:
   - Check **Automatically manage signing**
   - Select your **Team**
   - **Bundle Identifier**: `com.yourname.kext.Innie`
4. Build the project - it will be signed automatically

### Manual Signing (Command Line)

If you prefer command line signing:

```bash
# Sign the kernel extension
codesign --force --sign "Developer ID Application: Your Name (TEAMID)" \
         --entitlements Innie.entitlements \
         build/Release/Innie.kext

# Verify signature
codesign -vvv --deep --strict build/Release/Innie.kext
spctl -a -t exec -vv build/Release/Innie.kext
```

## Step 4: Create Entitlements File

Kernel extensions need specific entitlements:

**File: `Innie.entitlements`**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.driverkit.allow-any-userclient-access</key>
    <true/>
    <key>com.apple.developer.kernel.increased-memory-limit</key>
    <true/>
</dict>
</plist>
```

## Step 5: Notarization (Optional but Recommended)

For distribution, you should notarize the signed kernel extension:

```bash
# Create a ZIP for notarization
zip -r Innie-signed.zip build/Release/Innie.kext

# Submit for notarization
xcrun notarytool submit Innie-signed.zip \
                       --apple-id your-apple-id@example.com \
                       --team-id YOUR_TEAM_ID \
                       --password "your-app-specific-password" \
                       --wait

# Staple the notarization
xcrun stapler staple build/Release/Innie.kext
```

## Benefits of Code Signing

✅ **No SIP modification required** - kernel extension loads with SIP enabled
✅ **Better security** - maintains system integrity protection
✅ **Proper distribution** - signed kexts are trusted by macOS
✅ **Future compatibility** - Apple increasingly requires signed kernel extensions

## Installation with Signed Kext

With a properly signed kernel extension:
1. SIP can remain **enabled** (no Recovery Mode needed)
2. Standard installation process works
3. No security warnings or blocks
4. Professional distribution capability

## Cost Considerations

- **Individual Developer Account**: $99/year - sufficient for personal use
- **Organization Account**: $99/year - same capabilities for kernel extensions
- **Enterprise Account**: $299/year - NOT required for kernel extension signing

## Verification Commands

After signing, verify the signature:
```bash
# Check signature validity
codesign -vvv --deep --strict Innie.kext

# Check system acceptance
spctl -a -t exec -vv Innie.kext

# Verify it will load
kextutil -n -t Innie.kext
```

## Troubleshooting

**Certificate Issues:**
- Ensure certificates are installed in System keychain
- Check certificate expiration dates
- Verify Team ID matches in certificates and code

**Signing Failures:**
- Use `--deep` flag for embedded frameworks
- Include proper entitlements file
- Check for hardened runtime conflicts

**Loading Issues:**
- Verify signature after installation: `codesign -v /Library/Extensions/Innie.kext`
- Check system logs for signature validation errors
