#import "TouchingBarMediaRemote.h"
#import <AppKit/AppKit.h>
#import <dlfcn.h>

typedef void (*GetNowPlayingInfoFunction)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*GetApplicationPIDFunction)(dispatch_queue_t, void (^)(int));
typedef BOOL (*SendCommandFunction)(int, id);

static dispatch_queue_t TBMediaRemoteQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("app.touchingbar.media-remote", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static void *TBMediaRemoteHandle(void) {
    static void *handle;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY | RTLD_LOCAL);
    });
    return handle;
}

void TBMediaRemoteFetchNowPlaying(TBMediaRemoteCompletion completion) {
    if (completion == nil) { return; }
    void *handle = TBMediaRemoteHandle();
    GetNowPlayingInfoFunction getInfo = handle ? (GetNowPlayingInfoFunction)dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") : NULL;
    GetApplicationPIDFunction getPID = handle ? (GetApplicationPIDFunction)dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID") : NULL;
    if (getInfo == NULL) {
        completion(nil, nil);
        return;
    }

    dispatch_group_t group = dispatch_group_create();
    __block NSDictionary<NSString *, id> *information = nil;
    __block NSString *bundleIdentifier = nil;

    dispatch_group_enter(group);
    getInfo(TBMediaRemoteQueue(), ^(CFDictionaryRef info) {
        if (info != NULL) {
            information = [(__bridge NSDictionary *)info copy];
        }
        dispatch_group_leave(group);
    });

    if (getPID != NULL) {
        dispatch_group_enter(group);
        getPID(TBMediaRemoteQueue(), ^(int pid) {
            if (pid > 0) {
                NSRunningApplication *application = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
                bundleIdentifier = application.bundleIdentifier;
            }
            dispatch_group_leave(group);
        });
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
        completion(information, bundleIdentifier);
    });
}

BOOL TBMediaRemoteSendCommand(int command) {
    void *handle = TBMediaRemoteHandle();
    SendCommandFunction sendCommand = handle ? (SendCommandFunction)dlsym(handle, "MRMediaRemoteSendCommand") : NULL;
    if (sendCommand == NULL) { return NO; }
    return sendCommand(command, nil);
}
