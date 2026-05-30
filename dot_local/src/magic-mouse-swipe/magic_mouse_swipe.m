// magic-mouse-swipe
//
// Magic Mouse の天面を 2 本指で左右にスワイプしたら aerospace のワークスペースを
// prev / next へ切り替える常駐ツール。aerospace の ctrl-left / ctrl-right と同じ動作。
//
// トラックパッド用の aerospace-swipe は NSTouch (= トラックパッド専用) を使うため
// Magic Mouse のタッチを拾えない。こちらは非公開の MultitouchSupport.framework を
// 直接叩いて Magic Mouse の生タッチ (MTTouch) を受け取る。
//
// 参考:
//   - acsandmann/aerospace-swipe   (ジェスチャ判定の考え方)
//   - mhuusko5/M5MultitouchSupport (private API 宣言)
//
// build: clang -framework Foundation -framework IOKit \
//          -F/System/Library/PrivateFrameworks -framework MultitouchSupport \
//          -o magic-mouse-swipe magic_mouse_swipe.m

#import <Foundation/Foundation.h>

// ---- MultitouchSupport private API 宣言 --------------------------------------

typedef struct { float x; float y; } MTPoint;
typedef struct { MTPoint position; MTPoint velocity; } MTVector;

typedef int MTTouchState;

// 実際に使うのは normalizedPosition.position.x だけだが、private API の
// ABI に合わせるため全フィールドを正確に並べる (削るとレイアウトが崩れる)。
typedef struct {
    int frame;
    double timestamp;
    int identifier;
    MTTouchState state;
    int fingerId;
    int handId;
    MTVector normalizedPosition;
    float size;
    int field9;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absolutePosition;
    int field14;
    int field15;
    float density;
} MTTouch;

typedef void *MTDeviceRef;
typedef void (*MTFrameCallbackFunction)(MTDeviceRef device, MTTouch touches[],
                                        int numTouches, double timestamp, int frame);

extern CFMutableArrayRef MTDeviceCreateList(void);
extern void MTRegisterContactFrameCallback(MTDeviceRef, MTFrameCallbackFunction);
extern void MTUnregisterContactFrameCallback(MTDeviceRef, MTFrameCallbackFunction);
extern void MTDeviceStart(MTDeviceRef, int);
extern void MTDeviceStop(MTDeviceRef);
// 内蔵 (= トラックパッド) かどうか。Magic Mouse は false。
extern bool MTDeviceIsBuiltIn(MTDeviceRef) __attribute__((weak_import));

// ---- チューニング可能なパラメータ -------------------------------------------

// スワイプと認定する平均 x 移動量 (normalizedPosition は 0.0〜1.0)。
// Magic Mouse は「親指を置いて人差し指でスワイプ」する動きが多く、片指だけ
// 動くと平均 x の変化は実移動の半分になる。実測でその場合 ~0.13 動くので
// 0.06 を閾値にする (軽いスワイプでも反応するよう感度高め)。
static const double kSwipeThreshold = 0.06;

// ---- ジェスチャ状態 ----------------------------------------------------------
//
// 多重発火の根本原因 (同一 Magic Mouse の論理デバイス重複登録) は登録側で
// 1 台に絞って解消済み。そのためここはシンプルに保てる:
//   2 本指が乗っている間に基準点から閾値ぶん動いたら 1 回だけ発火し、
//   2 本指が外れたらリセットする。時間ガードは不要。
static double g_startX = 0.0;   // 2 本指が揃った時点の平均 x (基準点)
static BOOL   g_tracking = NO;  // 2 本指トラッキング中か
static BOOL   g_fired = NO;     // この 2 本指セッションで既に発火したか

static void run_aerospace(NSString *direction) {
    // "next" / "prev" を渡してワークスペースを切り替える。端では止まる (循環なし)。
    @autoreleasepool {
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:@"/opt/homebrew/bin/aerospace"];
        // aerospace v0.20+ は非 TTY からの暗黙 stdin を禁止したため --no-stdin が要る。
        // 循環はしない (端で止まる)。
        task.arguments = @[ @"workspace", @"--no-stdin", direction ];
        NSError *err = nil;
        if (![task launchAndReturnError:&err]) {
            fprintf(stderr, "[magic-mouse-swipe] failed to run aerospace: %s\n",
                    err.localizedDescription.UTF8String);
        }
    }
}

// ---- Multitouch コールバック -------------------------------------------------

static void contact_frame_callback(MTDeviceRef device, MTTouch touches[],
                                   int numTouches, double timestamp, int frame) {
    (void)device; (void)timestamp; (void)frame;

    if (numTouches < 2) {
        // 2 本指が外れたらセッション終了。次に 2 本載ったら基準点を取り直す。
        g_tracking = NO;
        g_fired = NO;
        return;
    }

    double avgX = (touches[0].normalizedPosition.position.x +
                   touches[1].normalizedPosition.position.x) / 2.0;

    if (!g_tracking) {
        // 2 本指が揃った最初のフレーム。ここを基準点にする。
        g_tracking = YES;
        g_fired = NO;
        g_startX = avgX;
        return;
    }

    if (g_fired) return; // この 2 本指セッションでは 1 回だけ発火。

    double dx = avgX - g_startX;
    if (fabs(dx) < kSwipeThreshold) return;

    // 指が右へ動いた (dx>0) → prev、左へ (dx<0) → next (ナチュラル方向)。
    NSString *dir = (dx > 0) ? @"prev" : @"next";
    run_aerospace(dir);
    g_fired = YES;
}

// ---- デバイス登録 (再接続追従) ----------------------------------------------

// 現在コールバックを張っている外付けデバイスのポインタ集合。常に 0 or 1 個。
static CFMutableSetRef g_watched = NULL;

// 現在のデバイス一覧と g_watched を突き合わせ、登録/解除を同期する。
// 起動時とタイマー (5 秒ごと) から呼ばれ、Magic Mouse のホットプラグに追従する。
//
// 注意: MTDeviceCreateList() は 1 台の物理 Magic Mouse に対して連番アドレスの
// 論理デバイスを複数返すことがある。全部に登録すると 1 回のスワイプが N 回
// 配送され多重発火する。そこで「外付けは 1 台だけ」登録する。
static void scan_and_register_devices(void) {
    CFMutableArrayRef devices = MTDeviceCreateList();
    if (!devices) return;
    CFIndex count = CFArrayGetCount(devices);

    // 現在存在する外付けデバイスの集合を作る (内蔵トラックパッドは除外)。
    CFMutableSetRef present = CFSetCreateMutable(NULL, 0, NULL);
    for (CFIndex i = 0; i < count; i++) {
        MTDeviceRef dev = (MTDeviceRef)CFArrayGetValueAtIndex(devices, i);
        if (MTDeviceIsBuiltIn && MTDeviceIsBuiltIn(dev)) continue;
        CFSetAddValue(present, dev);
    }

    // 1) 監視中なのにもう存在しない (= 切断された) デバイスを解除する。
    //    CFSet を走査しながら消せないので、いったん配列に移してから消す。
    CFIndex watchedCount = CFSetGetCount(g_watched);
    if (watchedCount > 0) {
        const void **w = malloc(sizeof(void *) * watchedCount);
        CFSetGetValues(g_watched, w);
        for (CFIndex i = 0; i < watchedCount; i++) {
            MTDeviceRef dev = (MTDeviceRef)w[i];
            if (!CFSetContainsValue(present, dev)) {
                MTDeviceStop(dev);
                MTUnregisterContactFrameCallback(dev, contact_frame_callback);
                CFSetRemoveValue(g_watched, dev);
                fprintf(stderr, "[magic-mouse-swipe] device %p disconnected\n", dev);
            }
        }
        free(w);
    }

    // 2) まだ 1 台も監視していなければ、外付けを 1 台だけ登録する。
    //    (切断後の再接続では別ポインタになるが、ここで新規として拾い直す)
    if (CFSetGetCount(g_watched) == 0) {
        for (CFIndex i = 0; i < count; i++) {
            MTDeviceRef dev = (MTDeviceRef)CFArrayGetValueAtIndex(devices, i);
            if (MTDeviceIsBuiltIn && MTDeviceIsBuiltIn(dev)) continue;
            MTRegisterContactFrameCallback(dev, contact_frame_callback);
            MTDeviceStart(dev, 0);
            CFSetAddValue(g_watched, dev);
            fprintf(stderr, "[magic-mouse-swipe] watching external device %p\n", dev);
            break; // 最初の 1 台だけ。残りの論理デバイスは無視。
        }
    }

    CFRelease(present);
    CFRelease(devices);
}

static void timer_callback(CFRunLoopTimerRef timer, void *info) {
    (void)timer; (void)info;
    scan_and_register_devices();
}

// ---- main --------------------------------------------------------------------

int main(int argc, const char *argv[]) {
    (void)argc; (void)argv;
    @autoreleasepool {
        g_watched = CFSetCreateMutable(NULL, 0, NULL);

        scan_and_register_devices(); // 起動時に今あるデバイスを登録
        fprintf(stderr, "[magic-mouse-swipe] started (polling for hot-plug every 5s)\n");

        // 5 秒ごとにデバイス一覧を取り直し、後から挿した Magic Mouse を拾う。
        CFRunLoopTimerRef timer = CFRunLoopTimerCreate(
            kCFAllocatorDefault,
            CFAbsoluteTimeGetCurrent() + 5.0, // 初回発火
            5.0,                              // 以降 5 秒間隔
            0, 0, timer_callback, NULL);
        CFRunLoopAddTimer(CFRunLoopGetMain(), timer, kCFRunLoopDefaultMode);

        CFRunLoopRun();
        CFRelease(timer);
    }
    return 0;
}
