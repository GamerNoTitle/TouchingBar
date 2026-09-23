#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^TBMediaRemoteCompletion)(NSDictionary<NSString *, id> * _Nullable nowPlayingInfo,
                                         NSString * _Nullable bundleIdentifier);

FOUNDATION_EXPORT void TBMediaRemoteFetchNowPlaying(TBMediaRemoteCompletion completion);

/// Commands use MediaRemote's documented private enum values:
/// 2 = toggle play/pause, 4 = next track, 5 = previous track.
FOUNDATION_EXPORT BOOL TBMediaRemoteSendCommand(int command);

NS_ASSUME_NONNULL_END
