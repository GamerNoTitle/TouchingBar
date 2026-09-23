#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Adds an item to the private system tray/control strip area used by the
/// system-modal Touch Bar APIs.
FOUNDATION_EXPORT void TBSystemTrayAddItem(NSTouchBarItem *item);

/// Removes an item previously added to the private system tray.
FOUNDATION_EXPORT void TBSystemTrayRemoveItem(NSTouchBarItem *item);

/// Marks a system tray item as present in Control Strip.
FOUNDATION_EXPORT void TBSetControlStripPresence(NSString *identifier, BOOL present);

/// Presents a Touch Bar as a system-modal bar, overriding the active app's bar.
FOUNDATION_EXPORT void TBPresentSystemModalTouchBar(NSTouchBar *touchBar,
                                                    NSString * _Nullable identifier,
                                                    BOOL hideControlStrip);

/// Dismisses a system-modal Touch Bar.
FOUNDATION_EXPORT void TBDismissSystemModalTouchBar(NSTouchBar *touchBar);

/// Hides the close button while the owning app is frontmost.
FOUNDATION_EXPORT void TBSetSystemModalShowsCloseBoxWhenFrontMost(BOOL show);

/// Sets all built-in keyboard backlights to 0...1.
FOUNDATION_EXPORT BOOL TBSetKeyboardBacklight(float level);

/// Locks the current user session immediately.
FOUNDATION_EXPORT BOOL TBLockScreen(void);

NS_ASSUME_NONNULL_END
