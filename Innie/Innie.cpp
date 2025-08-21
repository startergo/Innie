//
//  Innie.cpp
//  Innie
//
//  Copyright © 2021 cdf. All rights reserved.
//

#include <IOKit/IOLib.h>
#include <IOKit/IORegistryEntry.h>
#include <IOKit/IODeviceTreeSupport.h>

#include "Innie.hpp"

OSDefineMetaClassAndStructors(Innie, IOService)

bool Innie::init(OSDictionary *dict) {
    if (!IOService::init())
        return false;
    
    return true;
}

void Innie::free(void) {
    IOService::free();
}

IOService *Innie::probe(IOService *provider, SInt32 *score) {
    if (IOService::probe(provider, score)==0)
        return 0;
    
    return this;
}

bool Innie::start(IOService *provider) {
    DBGLOG("starting\n");
    
    if (!IOService::start(provider))
        return false;
    
    processRoot();
    IOService::registerService();
    return true;
}

void Innie::stop(IOService *provider) {
    IOService::stop(provider);
}


void Innie::processRoot() {
    if (auto entry = IORegistryEntry::fromPath("/", gIODTPlane)) {
        IORegistryEntry *pciRoot = nullptr;
        bool ready = false, found = false;
        size_t repeat = 0;
        do {
            if (auto iterator = entry->getChildIterator(gIODTPlane)) {
                while ((pciRoot = OSDynamicCast(IORegistryEntry, iterator->getNextObject())) != nullptr) {
                    const char *name = pciRoot->getName();
                    if (name && !strncmp("PC", name, 2)) {
                        if (ready) {
                            DBGLOG("found PCI root %s", pciRoot->getName());
                            found = true;
                            while (OSDynamicCast(OSBoolean, pciRoot->getProperty("IOPCIConfigured")) != kOSBooleanTrue) {
                                DBGLOG("waiting for PCI root to be configured");
                                IOSleep(10);
                            }
                            recurseBridge(pciRoot);
                        } else {
                            IOSleep(1000); // Wait for other roots
                            ready = true;
                            break;
                        }
                    }
                }
                iterator->release();
            }
        } while (repeat++ < 0x10000000 && !found);
        entry->release();
    }
}

void Innie::recurseBridge(IORegistryEntry *entry) {
    if (auto iterator = entry->getChildIterator(gIODTPlane)) {
        IORegistryEntry *childEntry = nullptr;
        
        // Go through child entries of bridge, finding every other bridge and every SATA and NVMe device
        while ((childEntry = OSDynamicCast(IORegistryEntry, iterator->getNextObject())) != nullptr) {
            uint32_t code = 0;
            if (auto class_code = childEntry->getProperty("class-code")) {
                if (auto codeData = OSDynamicCast(OSData, class_code)) {
                    code=*(uint32_t*)codeData->getBytesNoCopy();
                    if (code == classCode::SATADevice || code == classCode::NVMeDevice || code == classCode::RAIDDevice){
                        DBGLOG("found storage device %s with class code 0x%x", childEntry->getName(), code);
                        // Always process device, even if built-in exists (for consistency)
                        internalizeDevice(childEntry);
                        // Don't break - continue processing other devices in same bridge
                    }
                    else if (code == classCode::PCIBridge) {
                        DBGLOG("found bridge %s", childEntry->getName());
                        // Wait for bridge configuration with timeout
                        int timeout = 1000; // 10 second timeout (1000 iterations of 10ms each)
                        while (OSDynamicCast(OSBoolean, childEntry->getProperty("IOPCIConfigured")) != kOSBooleanTrue && timeout-- > 0) {
                            DBGLOG("waiting for PCI bridge to be configured (timeout: %d)", timeout);
                            IOSleep(10);
                        }
                        if (timeout > 0) {
                            recurseBridge(childEntry);
                        } else {
                            DBGLOG("timeout waiting for bridge %s configuration", childEntry->getName());
                        }
                    }
                }
            }
        }
        iterator->release();
    }
}
       
void Innie::internalizeDevice(IORegistryEntry *entry) {
    DBGLOG("processing device %s for internalization", entry->getName());
    
    // Always set built-in property (force override if exists)
    setBuiltIn(entry);
    
    // Wait for device to be resourced with timeout
    int timeout = 2000; // 20 second timeout (2000 iterations of 10ms each)
    while (OSDynamicCast(OSBoolean, entry->getProperty("IOPCIResourced")) != kOSBooleanTrue && timeout-- > 0) {
        DBGLOG("waiting for device to be resourced (timeout: %d)", timeout);
        IOSleep(10);
    }
    
    if (timeout <= 0) {
        DBGLOG("timeout waiting for device %s to be resourced", entry->getName());
        return;
    }
    
    // Multiple passes to ensure all driver entries are updated
    for (int pass = 0; pass < 3; pass++) {
        DBGLOG("updating properties pass %d for device %s", pass + 1, entry->getName());
        
        // Update properties on the device itself
        updateOtherProperties(entry);
        
        // Proceed to update driver entries in service plane
        if (auto driverIterator = IORegistryIterator::iterateOver(entry, gIOServicePlane, kIORegistryIterateRecursively)) {
            IORegistryEntry *driverEntry = nullptr;
            while ((driverEntry = OSDynamicCast(IORegistryEntry, driverIterator->getNextObject())) != nullptr) {
                if (driverEntry != entry) { // Don't update the same entry twice
                    DBGLOG("updating properties for driver entry %s", driverEntry->getName());
                    updateOtherProperties(driverEntry);
                }
            }
            driverIterator->release();
        }
        
        // Wait between passes to allow driver loading
        if (pass < 2) {
            IOSleep(100);
        }
    }
    
    DBGLOG("completed internalization for device %s", entry->getName());
}

void Innie::setBuiltIn(IORegistryEntry *entry) {
    if (entry) {
        // Use OSData with single byte value 0x01 for built-in property
        if (auto builtInData = OSData::withBytes("\x01", 1)) {
            DBGLOG("setting built-in property for %s", entry->getName());
            entry->setProperty("built-in", builtInData);
            builtInData->release();
        }
    }
}

void Innie::updateOtherProperties(IORegistryEntry *entry) {
    if (!entry) return;
    
    OSString *internal = OSString::withCString("Internal");
    OSString *internalIcon = OSString::withCString("Internal.icns");
    
    if (!internal || !internalIcon) {
        if (internal) internal->release();
        if (internalIcon) internalIcon->release();
        return;
    }
    
    // Force update Physical Interconnect Location (always set, don't check if exists)
    DBGLOG("setting Physical Interconnect Location to Internal for %s", entry->getName());
    entry->setProperty("Physical Interconnect Location", internal);
    
    // Update icon (always attempt to set)
    if (auto icon = entry->getProperty("IOMediaIcon")) {
        if (auto dict = OSDynamicCast(OSDictionary, icon)) {
            dict = OSDictionary::withDictionary(dict);
            if (dict) {
                DBGLOG("updating IOMediaIcon for %s", entry->getName());
                dict->setObject("IOBundleResourceFile", internalIcon);
                entry->setProperty("IOMediaIcon", dict);
                dict->release();
            }
        }
    }
    
    // Update protocol characteristics (force update)
    if (auto proto = entry->getProperty("Protocol Characteristics")) {
        if (auto dict = OSDynamicCast(OSDictionary, proto)) {
            dict = OSDictionary::withDictionary(dict);
            if (dict) {
                DBGLOG("updating Protocol Characteristics for %s", entry->getName());
                dict->setObject("Physical Interconnect Location", internal);
                entry->setProperty("Protocol Characteristics", dict);
                dict->release();
            }
        }
    } else {
        // Create Protocol Characteristics if it doesn't exist
        DBGLOG("creating Protocol Characteristics for %s", entry->getName());
        if (auto newDict = OSDictionary::withCapacity(1)) {
            newDict->setObject("Physical Interconnect Location", internal);
            entry->setProperty("Protocol Characteristics", newDict);
            newDict->release();
        }
    }
    
    // Also set built-in at this level for good measure
    setBuiltIn(entry);
    
    internal->release();
    internalIcon->release();
}
