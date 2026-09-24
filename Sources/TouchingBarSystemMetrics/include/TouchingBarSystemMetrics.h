#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    double cpuUsagePercent;
    double gpuUsagePercent;
    double memoryUsagePercent;
    double diskUsagePercent;
    double cpuTemperatureCelsius;
    double fanRPM;
    double networkUploadBytesPerSecond;
    double networkDownloadBytesPerSecond;
    BOOL hasCPUUsage;
    BOOL hasGPUUsage;
    BOOL hasMemoryUsage;
    BOOL hasDiskUsage;
    BOOL hasCPUTemperature;
    BOOL hasFanRPM;
    BOOL hasNetworkUsage;
} TBSystemMetricsSnapshot;

FOUNDATION_EXPORT TBSystemMetricsSnapshot TBSystemMetricsSample(void);

NS_ASSUME_NONNULL_END
