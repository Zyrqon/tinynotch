// Мост к приватному MediaRemote.framework.
// Начиная с macOS 15.4 сторонние процессы не могут читать Now Playing напрямую,
// поэтому эта библиотека загружается в системный /usr/bin/perl (у него есть нужные права)
// и транслирует состояние плеера в stdout строками JSON, а команды принимает из stdin.

#import <Foundation/Foundation.h>
#include <dlfcn.h>

typedef void (*MRGetNowPlayingInfoFn)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*MRGetIsPlayingFn)(dispatch_queue_t, void (^)(BOOL));
typedef void (*MRGetClientFn)(dispatch_queue_t, void (^)(id));
typedef NSString *(*MRClientGetStringFn)(id);
typedef void (*MRRegisterFn)(dispatch_queue_t);
typedef BOOL (*MRSendCommandFn)(int, NSDictionary *);
typedef void (*MRSetElapsedFn)(double);

static MRGetNowPlayingInfoFn MRGetInfo;
static MRGetIsPlayingFn MRGetIsPlaying;
static MRGetClientFn MRGetClient;
static MRClientGetStringFn MRClientBundle;
static MRClientGetStringFn MRClientParentBundle;
static MRRegisterFn MRRegister;
static MRSendCommandFn MRSendCommand;
static MRSetElapsedFn MRSetElapsed;

static dispatch_queue_t queue;
static NSUInteger lastArtworkHash = 0;
static dispatch_source_t debounceTimer;

static void emit(NSDictionary *payload) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!json) return;
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static id jsonSafe(id value) {
    if (!value) return [NSNull null];
    if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]]) return value;
    return [NSNull null];
}

static void publish(void) {
    MRGetClient(queue, ^(id client) {
        NSString *bundle = client && MRClientBundle ? MRClientBundle(client) : nil;
        NSString *parent = client && MRClientParentBundle ? MRClientParentBundle(client) : nil;
        MRGetIsPlaying(queue, ^(BOOL playing) {
            MRGetInfo(queue, ^(NSDictionary *info) {
                NSMutableDictionary *out = [NSMutableDictionary dictionary];
                out[@"type"] = @"state";
                out[@"playing"] = @(playing);
                out[@"bundle"] = jsonSafe(bundle);
                out[@"parentBundle"] = jsonSafe(parent);
                if (info.count == 0) {
                    out[@"empty"] = @YES;
                    lastArtworkHash = 0;
                    emit(out);
                    return;
                }
                out[@"title"] = jsonSafe(info[@"kMRMediaRemoteNowPlayingInfoTitle"]);
                out[@"artist"] = jsonSafe(info[@"kMRMediaRemoteNowPlayingInfoArtist"]);
                out[@"album"] = jsonSafe(info[@"kMRMediaRemoteNowPlayingInfoAlbum"]);
                out[@"duration"] = jsonSafe(info[@"kMRMediaRemoteNowPlayingInfoDuration"]);
                out[@"elapsed"] = jsonSafe(info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"]);
                out[@"rate"] = jsonSafe(info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"]);
                NSDate *ts = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
                if ([ts isKindOfClass:[NSDate class]]) out[@"timestamp"] = @(ts.timeIntervalSince1970);

                NSData *art = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                if ([art isKindOfClass:[NSData class]] && art.length > 0) {
                    NSUInteger hash = art.length ^ (art.hash << 1);
                    if (hash != lastArtworkHash) {
                        lastArtworkHash = hash;
                        out[@"artwork"] = [art base64EncodedStringWithOptions:0];
                    }
                    out[@"hasArtwork"] = @YES;
                } else {
                    lastArtworkHash = 0;
                    out[@"hasArtwork"] = @NO;
                }
                emit(out);
            });
        });
    });
}

// MediaRemote присылает пачки уведомлений — схлопываем их в одно обновление.
static void schedulePublish(void) {
    dispatch_source_set_timer(debounceTimer, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_MSEC),
                              DISPATCH_TIME_FOREVER, 10 * NSEC_PER_MSEC);
}

static void handleCommand(NSString *line) {
    NSArray<NSString *> *parts = [line componentsSeparatedByString:@" "];
    NSString *cmd = parts.firstObject;
    if ([cmd isEqualToString:@"toggle"]) MRSendCommand(2, nil);
    else if ([cmd isEqualToString:@"play"]) MRSendCommand(0, nil);
    else if ([cmd isEqualToString:@"pause"]) MRSendCommand(1, nil);
    else if ([cmd isEqualToString:@"next"]) MRSendCommand(4, nil);
    else if ([cmd isEqualToString:@"previous"]) MRSendCommand(5, nil);
    else if ([cmd isEqualToString:@"seek"] && parts.count > 1 && MRSetElapsed) MRSetElapsed(parts[1].doubleValue);
    else if ([cmd isEqualToString:@"refresh"]) { lastArtworkHash = 0; schedulePublish(); }
}

static BOOL loadMediaRemote(void) {
    void *h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!h) return NO;
    MRGetInfo = dlsym(h, "MRMediaRemoteGetNowPlayingInfo");
    MRGetIsPlaying = dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    MRGetClient = dlsym(h, "MRMediaRemoteGetNowPlayingClient");
    MRClientBundle = dlsym(h, "MRNowPlayingClientGetBundleIdentifier");
    MRClientParentBundle = dlsym(h, "MRNowPlayingClientGetParentAppBundleIdentifier");
    MRRegister = dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications");
    MRSendCommand = dlsym(h, "MRMediaRemoteSendCommand");
    MRSetElapsed = dlsym(h, "MRMediaRemoteSetElapsedTime");
    return MRGetInfo && MRGetIsPlaying && MRGetClient && MRRegister && MRSendCommand;
}

// Точка входа: вызывается из perl как XSUB, аргументы интерпретатора игнорируются.
__attribute__((visibility("default")))
void island_media_stream(void) {
    @autoreleasepool {
        if (!loadMediaRemote()) {
            emit(@{ @"type": @"error", @"message": @"MediaRemote unavailable" });
            exit(1);
        }
        queue = dispatch_queue_create("island.media", DISPATCH_QUEUE_SERIAL);
        debounceTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
        dispatch_source_set_event_handler(debounceTimer, ^{ publish(); });
        dispatch_source_set_timer(debounceTimer, DISPATCH_TIME_FOREVER, DISPATCH_TIME_FOREVER, 0);
        dispatch_resume(debounceTimer);

        MRRegister(dispatch_get_main_queue());
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        for (NSString *name in @[ @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                                  @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                                  @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
                                  @"kMRMediaRemoteNowPlayingApplicationClientStateDidChange" ]) {
            [nc addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *n) {
                dispatch_async(queue, ^{ schedulePublish(); });
            }];
        }

        emit(@{ @"type": @"ready" });
        dispatch_async(queue, ^{ schedulePublish(); });

        // Команды из stdin. EOF означает, что приложение закрылось.
        [NSThread detachNewThreadWithBlock:^{
            char buf[512];
            while (fgets(buf, sizeof buf, stdin)) {
                NSString *line = [[NSString stringWithUTF8String:buf]
                    stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                if (line.length == 0) continue;
                dispatch_async(queue, ^{ handleCommand(line); });
            }
            exit(0);
        }];

        [[NSRunLoop mainRunLoop] run];
    }
}
