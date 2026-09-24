#import "TouchingBarSystemMetrics.h"
#import <IOKit/IOKitLib.h>
#import <IOKit/ps/IOPowerSources.h>
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <net/if.h>
#import <ifaddrs.h>
#import <net/if_dl.h>
#import <sys/mount.h>
#import <sys/sysctl.h>
#import <mach-o/dyld.h>

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} SMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCPLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} SMCKeyInfoData;

typedef struct {
    uint32_t key;
    SMCVersion vers;
    SMCPLimitData pLimitData;
    SMCKeyInfoData keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCKeyData;

static io_connect_t gSMCConnection = MACH_PORT_NULL;
static NSLock *gSMCLock;

static uint32_t TBFourCC(NSString *value) {
    const char *chars = value.UTF8String;
    if (strlen(chars) < 4) { return 0; }
    return ((uint32_t)(uint8_t)chars[0] << 24)
         | ((uint32_t)(uint8_t)chars[1] << 16)
         | ((uint32_t)(uint8_t)chars[2] << 8)
         | (uint32_t)(uint8_t)chars[3];
}

static BOOL TBOpenSMC(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gSMCLock = [NSLock new];
        io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
        if (service != MACH_PORT_NULL) {
            kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &gSMCConnection);
            if (getenv("TOUCHINGBAR_SMC_DEBUG") != NULL) {
                fprintf(stderr, "SMC open result=0x%x connection=%u\n", result, gSMCConnection);
            }
            IOObjectRelease(service);
        }
    });
    return gSMCConnection != MACH_PORT_NULL;
}

static BOOL TBReadSMCKey(uint32_t key, SMCKeyData *output) {
    if (!TBOpenSMC()) { return NO; }
    [gSMCLock lock];
    SMCKeyData input = {0};
    input.key = key;
    input.data8 = 9;
    size_t outputSize = sizeof(SMCKeyData);
    kern_return_t result = IOConnectCallStructMethod(gSMCConnection, 2, &input, sizeof(input), output, &outputSize);
    if (result != KERN_SUCCESS || output->result != 0) {
        if (getenv("TOUCHINGBAR_SMC_DEBUG") != NULL) {
            fprintf(stderr, "SMC key info failed key=%08x kr=0x%x result=%u status=%u\n", key, result, output->result, output->status);
        }
        [gSMCLock unlock];
        return NO;
    }

    uint32_t dataSize = output->keyInfo.dataSize;
    uint32_t dataType = output->keyInfo.dataType;
    input.keyInfo = output->keyInfo;
    input.data8 = 5;
    outputSize = sizeof(SMCKeyData);
    result = IOConnectCallStructMethod(gSMCConnection, 2, &input, sizeof(input), output, &outputSize);
    if (result == KERN_SUCCESS && output->result == 0 && dataSize > 0) {
        output->keyInfo.dataSize = dataSize;
        output->keyInfo.dataType = dataType;
    }
    BOOL success = result == KERN_SUCCESS && output->result == 0 && dataSize > 0;
    if (getenv("TOUCHINGBAR_SMC_DEBUG") != NULL) {
        fprintf(stderr, "SMC read key=%08x kr=0x%x result=%u status=%u size=%u bytes=%02x %02x %02x %02x\n", key, result, output->result, output->status, dataSize, output->bytes[0], output->bytes[1], output->bytes[2], output->bytes[3]);
    }
    [gSMCLock unlock];
    return success;
}

static double TBReadTemperature(NSArray<NSString *> *keys) {
    for (NSString *keyString in keys) {
        SMCKeyData data = {0};
        if (TBReadSMCKey(TBFourCC(keyString), &data) && data.keyInfo.dataSize >= 2) {
            double value = (double)(int8_t)data.bytes[0] + (double)data.bytes[1] / 256.0;
            if (value > 0 && value < 125) { return value; }
        }
    }
    return 0;
}

static double TBReadFanRPM(void) {
    SMCKeyData countData = {0};
    if (!TBReadSMCKey(TBFourCC(@"FNum"), &countData) || countData.bytes[0] == 0) { return 0; }
    double maximum = 0;
    for (uint8_t index = 0; index < countData.bytes[0] && index < 8; index++) {
        NSString *key = [NSString stringWithFormat:@"F%uAc", index];
        SMCKeyData data = {0};
        if (TBReadSMCKey(TBFourCC(key), &data) && data.keyInfo.dataSize >= 2) {
            double value;
            if (data.keyInfo.dataType == TBFourCC(@"flt ") && data.keyInfo.dataSize >= 4) {
                float floatValue;
                memcpy(&floatValue, data.bytes, sizeof(floatValue));
                value = floatValue;
            } else {
                value = ((double)data.bytes[0] * 256.0 + (double)data.bytes[1]) / 4.0;
            }
            maximum = MAX(maximum, value);
        }
    }
    return maximum;
}

static NSDictionary *TBSmartBatteryProperties(void) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"));
    if (service == MACH_PORT_NULL) { return nil; }
    CFMutableDictionaryRef properties = NULL;
    NSDictionary *result = nil;
    if (IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS && properties) {
        result = CFBridgingRelease(properties);
    }
    IOObjectRelease(service);
    return result;
}

static void TBBatterySample(TBSystemMetricsSnapshot *result) {
    CFTypeRef powerInfo = IOPSCopyPowerSourcesInfo();
    if (powerInfo) {
        CFArrayRef sources = IOPSCopyPowerSourcesList(powerInfo);
        if (sources) {
            for (CFIndex index = 0; index < CFArrayGetCount(sources); index++) {
                CFTypeRef source = CFArrayGetValueAtIndex(sources, index);
                NSDictionary *description = (__bridge NSDictionary *)IOPSGetPowerSourceDescription(powerInfo, source);
                NSString *sourceType = description[@(kIOPSTypeKey)];
                if (sourceType && ![sourceType isEqualToString:@(kIOPSInternalBatteryType)]) { continue; }
                NSNumber *currentCapacity = description[@(kIOPSCurrentCapacityKey)];
                NSNumber *maxCapacity = description[@(kIOPSMaxCapacityKey)];
                if (currentCapacity && maxCapacity && maxCapacity.doubleValue > 0) {
                    result->batteryLevelPercent = MIN(100.0, MAX(0.0, 100.0 * currentCapacity.doubleValue / maxCapacity.doubleValue));
                    result->hasBatteryLevel = YES;
                }
                if (description[@(kIOPSIsChargingKey)]) {
                    result->batteryIsCharging = [description[@(kIOPSIsChargingKey)] boolValue];
                }
                if (description[@(kIOPSIsChargedKey)]) {
                    result->batteryIsFullyCharged = [description[@(kIOPSIsChargedKey)] boolValue];
                }
                NSString *state = description[@(kIOPSPowerSourceStateKey)];
                if ([state isEqualToString:@(kIOPSACPowerValue)]) {
                    result->batteryIsPluggedIn = YES;
                } else if ([state isEqualToString:@(kIOPSBatteryPowerValue)]) {
                    result->batteryIsPluggedIn = NO;
                }
                NSNumber *time = result->batteryIsCharging
                    ? description[@(kIOPSTimeToFullChargeKey)]
                    : description[@(kIOPSTimeToEmptyKey)];
                if (time && time.integerValue > 0 && time.integerValue < 65535) {
                    result->batteryTimeMinutes = time.doubleValue;
                    result->hasBatteryTime = YES;
                }
            }
            CFRelease(sources);
        }
        CFRelease(powerInfo);
    }

    NSDictionary *battery = TBSmartBatteryProperties();
    if (battery) {
        if (!result->hasBatteryLevel) {
            NSNumber *currentCapacity = battery[@"CurrentCapacity"] ?: battery[@"AppleRawCurrentCapacity"];
            NSNumber *maxCapacity = battery[@"MaxCapacity"] ?: battery[@"AppleRawMaxCapacity"];
            if (currentCapacity && maxCapacity && maxCapacity.doubleValue > 0) {
                result->batteryLevelPercent = MIN(100.0, MAX(0.0, 100.0 * currentCapacity.doubleValue / maxCapacity.doubleValue));
                result->hasBatteryLevel = YES;
            }
        }
        NSNumber *externalConnected = battery[@"ExternalConnected"];
        NSNumber *isCharging = battery[@"IsCharging"];
        NSNumber *fullyCharged = battery[@"FullyCharged"];
        if (externalConnected) { result->batteryIsPluggedIn = externalConnected.boolValue; }
        if (isCharging) { result->batteryIsCharging = isCharging.boolValue; }
        if (fullyCharged) { result->batteryIsFullyCharged = fullyCharged.boolValue; }

        NSDictionary *telemetry = battery[@"PowerTelemetryData"];
        NSNumber *systemPowerIn = telemetry[@"SystemPowerIn"];
        if (systemPowerIn && systemPowerIn.doubleValue > 0) {
            result->batteryPowerWatts = systemPowerIn.doubleValue / 1000.0;
            result->hasBatteryPower = YES;
        } else {
            NSNumber *amperage = battery[@"InstantAmperage"] ?: battery[@"Amperage"];
            NSNumber *voltage = battery[@"Voltage"];
            if (amperage && voltage) {
                uint64_t rawAmperage = amperage.unsignedLongLongValue;
                int64_t signedAmperage;
                if (rawAmperage > INT64_MAX) {
                    signedAmperage = -(int64_t)(UINT64_MAX - rawAmperage + 1);
                } else {
                    signedAmperage = (int64_t)rawAmperage;
                }
                double watts = fabs((double)signedAmperage * voltage.doubleValue / 1000000.0);
                if (watts > 0.01) {
                    result->batteryPowerWatts = watts;
                    result->hasBatteryPower = YES;
                }
            }
        }

        if (!result->hasBatteryTime) {
            NSNumber *time = result->batteryIsCharging ? battery[@"AvgTimeToFull"] : battery[@"AvgTimeToEmpty"];
            if (!time) {
                time = result->batteryIsCharging ? battery[@"TimeToFullCharge"] : battery[@"TimeRemaining"];
            }
            if (time && time.integerValue > 0 && time.integerValue < 65535) {
                result->batteryTimeMinutes = time.doubleValue;
                result->hasBatteryTime = YES;
            }
        }
    }
}

static double TBCPUUsage(void) {
    static host_cpu_load_info_data_t previous;
    static BOOL hasPrevious = NO;
    static NSLock *lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ lock = [NSLock new]; });
    mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
    host_cpu_load_info_data_t current;
    if (host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, (host_info_t)&current, &count) != KERN_SUCCESS) {
        return 0;
    }

    [lock lock];
    if (!hasPrevious) {
        previous = current;
        hasPrevious = YES;
        [lock unlock];
        return 0;
    }
    uint64_t user = current.cpu_ticks[CPU_STATE_USER] - previous.cpu_ticks[CPU_STATE_USER];
    uint64_t system = current.cpu_ticks[CPU_STATE_SYSTEM] - previous.cpu_ticks[CPU_STATE_SYSTEM];
    uint64_t nice = current.cpu_ticks[CPU_STATE_NICE] - previous.cpu_ticks[CPU_STATE_NICE];
    uint64_t idle = current.cpu_ticks[CPU_STATE_IDLE] - previous.cpu_ticks[CPU_STATE_IDLE];
    previous = current;
    [lock unlock];
    uint64_t total = user + system + nice + idle;
    return total == 0 ? 0 : 100.0 * (double)(user + system + nice) / (double)total;
}

static double TBMemoryUsage(void) {
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    vm_statistics64_data_t stats;
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64, (host_info64_t)&stats, &count) != KERN_SUCCESS) {
        return 0;
    }
    uint64_t pageSize = vm_kernel_page_size;
    uint64_t used = ((uint64_t)stats.active_count + stats.wire_count + stats.compressor_page_count) * pageSize;
    uint64_t total = 0;
    size_t size = sizeof(total);
    if (sysctlbyname("hw.memsize", &total, &size, NULL, 0) != 0 || total == 0) { return 0; }
    return MIN(100.0, 100.0 * (double)used / (double)total);
}

static double TBDiskUsage(void) {
    struct statfs stats;
    if (statfs("/", &stats) != 0 || stats.f_blocks == 0) { return 0; }
    uint64_t used = stats.f_blocks - stats.f_bfree;
    return 100.0 * (double)used / (double)stats.f_blocks;
}

static double TBGPUUsage(void) {
    io_iterator_t iterator = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) != KERN_SUCCESS) {
        return 0;
    }
    double best = 0;
    io_registry_entry_t entry;
    while ((entry = IOIteratorNext(iterator))) {
        CFMutableDictionaryRef properties = NULL;
        if (IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS && properties) {
            NSDictionary *dictionary = CFBridgingRelease(properties);
            NSDictionary *statistics = dictionary[@"PerformanceStatistics"];
            NSArray *keys = @[@"Device Utilization %", @"GPU Activity(%)", @"GPU Core Utilization"];
            for (NSString *key in keys) {
                NSNumber *value = statistics[key];
                if ([value isKindOfClass:NSNumber.class]) {
                    best = MAX(best, value.doubleValue);
                }
            }
        }
        IOObjectRelease(entry);
    }
    IOObjectRelease(iterator);
    return MIN(100.0, MAX(0.0, best));
}

static void TBNetworkBytes(uint64_t *received, uint64_t *sent) {
    struct ifaddrs *addresses = NULL;
    *received = 0;
    *sent = 0;
    if (getifaddrs(&addresses) != 0) { return; }
    for (struct ifaddrs *address = addresses; address; address = address->ifa_next) {
        if (address->ifa_addr == NULL || address->ifa_addr->sa_family != AF_LINK) { continue; }
        if ((address->ifa_flags & IFF_LOOPBACK) != 0) { continue; }
        struct if_data *data = (struct if_data *)address->ifa_data;
        if (data == NULL) { continue; }
        *received += data->ifi_ibytes;
        *sent += data->ifi_obytes;
    }
    freeifaddrs(addresses);
}

TBSystemMetricsSnapshot TBSystemMetricsSample(void) {
    TBSystemMetricsSnapshot result = {0};
    result.cpuUsagePercent = TBCPUUsage();
    result.hasCPUUsage = result.cpuUsagePercent > 0;
    result.gpuUsagePercent = TBGPUUsage();
    result.hasGPUUsage = result.gpuUsagePercent > 0;
    result.memoryUsagePercent = TBMemoryUsage();
    result.hasMemoryUsage = result.memoryUsagePercent > 0;
    result.diskUsagePercent = TBDiskUsage();
    result.hasDiskUsage = result.diskUsagePercent > 0;
    result.cpuTemperatureCelsius = TBReadTemperature(@[@"TC0P", @"TC0D", @"TC0F", @"TC0H", @"TCXC", @"TCSA"]);
    result.hasCPUTemperature = result.cpuTemperatureCelsius > 0;
    result.fanRPM = TBReadFanRPM();
    result.hasFanRPM = result.fanRPM > 0;

    static uint64_t previousReceived, previousSent;
    static NSTimeInterval previousTime;
    static NSLock *networkLock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ networkLock = [NSLock new]; });
    uint64_t received, sent;
    TBNetworkBytes(&received, &sent);
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    [networkLock lock];
    if (previousTime > 0 && now > previousTime) {
        double interval = now - previousTime;
        result.networkDownloadBytesPerSecond = MAX(0, (double)(received - previousReceived) / interval);
        result.networkUploadBytesPerSecond = MAX(0, (double)(sent - previousSent) / interval);
        result.hasNetworkUsage = YES;
    }
    previousReceived = received;
    previousSent = sent;
    previousTime = now;
    [networkLock unlock];

    TBBatterySample(&result);
    return result;
}
