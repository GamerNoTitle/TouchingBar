#import "TouchingBarDFR.h"
#import <dlfcn.h>
#import <objc/message.h>

static void (*PaletteSetControlStripPresence)(NSString *, BOOL);
static BOOL hasLoadedPrivateFramework;

static void TBLoadPrivateFramework(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY | RTLD_LOCAL);
        if (handle != NULL) {
            PaletteSetControlStripPresence = (void (*)(NSString *, BOOL))dlsym(handle, "DFRElementSetControlStripPresenceForIdentifier");
        }
        hasLoadedPrivateFramework = YES;
    });
}

void TBSystemTrayAddItem(NSTouchBarItem *item) {
    SEL selector = NSSelectorFromString(@"addSystemTrayItem:");
    Class cls = NSClassFromString(@"NSTouchBarItem");
    if ([cls respondsToSelector:selector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(cls, selector, item);
    }
}

void TBSystemTrayRemoveItem(NSTouchBarItem *item) {
    SEL selector = NSSelectorFromString(@"removeSystemTrayItem:");
    Class cls = NSClassFromString(@"NSTouchBarItem");
    if ([cls respondsToSelector:selector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(cls, selector, item);
    }
}

void TBSetControlStripPresence(NSString *identifier, BOOL present) {
    TBLoadPrivateFramework();
    if (PaletteSetControlStripPresence != NULL) {
        PaletteSetControlStripPresence(identifier, present);
    }
}

void TBPresentSystemModalTouchBar(NSTouchBar *touchBar,
                                  NSString * _Nullable identifier,
                                  BOOL hideControlStrip) {
    Class cls = NSClassFromString(@"NSTouchBar");
    SEL selector = NSSelectorFromString(@"presentSystemModalTouchBar:placement:systemTrayItemIdentifier:");
    Method method = class_getClassMethod(cls, selector);
    if (method != NULL) {
        typedef void (*PresentFunction)(id, SEL, NSTouchBar *, int64_t, NSString *);
        PresentFunction present = (PresentFunction)method_getImplementation(method);
        present(cls, selector, touchBar, hideControlStrip ? 1 : 0, identifier);
        return;
    }

    selector = NSSelectorFromString(@"presentSystemModalFunctionBar:placement:systemTrayItemIdentifier:");
    method = class_getClassMethod(cls, selector);
    if (method != NULL) {
        typedef void (*PresentFunction)(id, SEL, NSTouchBar *, int64_t, NSString *);
        PresentFunction present = (PresentFunction)method_getImplementation(method);
        present(cls, selector, touchBar, hideControlStrip ? 1 : 0, identifier);
    }
}

void TBDismissSystemModalTouchBar(NSTouchBar *touchBar) {
    Class cls = NSClassFromString(@"NSTouchBar");
    SEL selector = NSSelectorFromString(@"dismissSystemModalTouchBar:");
    Method method = class_getClassMethod(cls, selector);
    if (method != NULL) {
        typedef void (*DismissFunction)(id, SEL, NSTouchBar *);
        DismissFunction dismiss = (DismissFunction)method_getImplementation(method);
        dismiss(cls, selector, touchBar);
        return;
    }

    selector = NSSelectorFromString(@"dismissSystemModalFunctionBar:");
    method = class_getClassMethod(cls, selector);
    if (method != NULL) {
        typedef void (*DismissFunction)(id, SEL, NSTouchBar *);
        DismissFunction dismiss = (DismissFunction)method_getImplementation(method);
        dismiss(cls, selector, touchBar);
    }
}

void TBSetSystemModalShowsCloseBoxWhenFrontMost(BOOL show) {
    TBLoadPrivateFramework();
    void *handle = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY | RTLD_LOCAL);
    if (handle == NULL) {
        return;
    }
    void (*setter)(BOOL) = (void (*)(BOOL))dlsym(handle, "DFRSystemModalShowsCloseBoxWhenFrontMost");
    if (setter != NULL) {
        setter(show);
    }
}


BOOL TBGetKeyboardBacklight(float *level) {
    if (level == NULL) { return NO; }
    void *handle = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY | RTLD_LOCAL);
    if (handle == NULL) { return NO; }
    Class cls = NSClassFromString(@"KeyboardBrightnessClient");
    if (cls == Nil) { return NO; }
    id client = [[cls alloc] init];
    SEL idsSelector = NSSelectorFromString(@"copyKeyboardBacklightIDs");
    SEL getSelector = NSSelectorFromString(@"brightnessForKeyboard:");
    if (![client respondsToSelector:idsSelector] || ![client respondsToSelector:getSelector]) { return NO; }

    NSArray *identifiers = ((id (*)(id, SEL))objc_msgSend)(client, idsSelector);
    typedef float (*GetBrightnessFunction)(id, SEL, unsigned long long);
    GetBrightnessFunction getBrightness = (GetBrightnessFunction)objc_msgSend;
    if (identifiers.count == 0) {
        *level = getBrightness(client, getSelector, 0);
        return YES;
    }
    for (NSNumber *identifier in identifiers) {
        *level = getBrightness(client, getSelector, identifier.unsignedLongLongValue);
        return YES;
    }
    return NO;
}

BOOL TBSetKeyboardBacklight(float level) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY | RTLD_LOCAL);
    if (handle == NULL) { return NO; }
    Class cls = NSClassFromString(@"KeyboardBrightnessClient");
    if (cls == Nil) { return NO; }
    id client = [[cls alloc] init];
    SEL idsSelector = NSSelectorFromString(@"copyKeyboardBacklightIDs");
    SEL setSelector = NSSelectorFromString(@"setBrightness:forKeyboard:");
    SEL autoSelector = NSSelectorFromString(@"enableAutoBrightness:forKeyboard:");
    if (![client respondsToSelector:idsSelector] || ![client respondsToSelector:setSelector]) { return NO; }

    NSArray *identifiers = ((id (*)(id, SEL))objc_msgSend)(client, idsSelector);
    typedef BOOL (*SetBrightnessFunction)(id, SEL, float, unsigned long long);
    typedef BOOL (*SetAutoBrightnessFunction)(id, SEL, BOOL, unsigned long long);
    SetBrightnessFunction setBrightness = (SetBrightnessFunction)objc_msgSend;
    SetAutoBrightnessFunction setAutoBrightness = (SetAutoBrightnessFunction)objc_msgSend;

    BOOL changed = NO;
    if (identifiers.count == 0) {
        if ([client respondsToSelector:autoSelector]) {
            setAutoBrightness(client, autoSelector, NO, 0);
        }
        changed = setBrightness(client, setSelector, level, 0);
    } else {
        for (NSNumber *identifier in identifiers) {
            unsigned long long keyboardID = identifier.unsignedLongLongValue;
            if ([client respondsToSelector:autoSelector]) {
                setAutoBrightness(client, autoSelector, NO, keyboardID);
            }
            changed = setBrightness(client, setSelector, level, keyboardID) || changed;
        }
    }
    return changed;
}

BOOL TBLockScreen(void) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/A/login", RTLD_LAZY | RTLD_LOCAL);
    if (handle == NULL) { return NO; }
    typedef int (*LockScreenFunction)(void);
    LockScreenFunction lockScreen = (LockScreenFunction)dlsym(handle, "SACLockScreenImmediate");
    if (lockScreen == NULL) { return NO; }
    return lockScreen() == 0;
}
