// aerospace-swipe-mini
//
// トラックパッドの 4 本指スワイプで aerospace を操作する常駐ツール。
//   - 水平スワイプ → ワークスペース切替 (workspace prev / next)
//   - 垂直スワイプ → モニター間フォーカス移動 (focus-monitor)
//
// OSS の acsandmann/aerospace-swipe は水平スワイプ (workspace prev/next) しか持たず、
// 垂直スワイプによるモニター移動が無い。本ツールはそこを埋める自作の代替。
//
// 入力は CGEventTap の NSEventTypeGesture + 公開 NSTouch API で読む。
// MultitouchSupport の device 登録ではないので stale-device 問題がなく、スリープ
// 復帰や高負荷で tap が無効化されても event_callback 内で inline に再有効化する。
// 必要権限は Accessibility (Input Monitoring ではない)。
//
// tap は listen-only ではなく default モード。4 本指の指移動は gesture とは別に
// scrollWheel イベントとしてもアプリに配送され、それが Ghostty/VSCode/Chrome 等の
// スクロール漏れの実体。gesture を食うだけでは止まらないので、4 本指が乗っている間
// (g_suppressScroll) の scrollWheel を NULL で食う。通常の 2 本指スクロールや
// マウスホイールは抑制対象外なので素通しする。
//
// 兄弟ツール magic-mouse-swipe は Magic Mouse 用に非公開 MultitouchSupport を叩くが、
// こちらはトラックパッド (= NSTouch) 専用なので framework が異なる点に注意。
//
// build: clang -framework Cocoa -framework ApplicationServices \
//          -o aerospace-swipe-mini main.m

#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#include <signal.h>
#include <unistd.h>

// ---- チューニング可能なパラメータ -------------------------------------------

static const int    kFingers        = 4;
// スワイプと認定する平均移動量 (normalizedPosition は 0.0〜1.0)。
static const double kSwipeThreshold = 0.04;
// 1 回発火したあと同一ジェスチャで再発火しないためのクールダウン。
static const double kCooldownSec    = 0.10;
static const char  *kAerospacePath  = "/opt/homebrew/bin/aerospace";

// 垂直スワイプの飛び先。monitor-pattern で指定 (ディスプレイ名のリネーム耐性のため
// "secondary" / "built-in" を使う。aerospace.toml の force-assignment と同じ語彙)。
static const char  *kMonitorUp      = "secondary"; // 上スワイプ → 外部ディスプレイ
static const char  *kMonitorDown    = "built-in";  // 下スワイプ → 内蔵 Retina

// ---- ジェスチャ状態 ----------------------------------------------------------

static double          g_startX        = 0.0; // 4 本指が揃った時点の平均 x (基準点)
static double          g_startY        = 0.0; // 同 y
static BOOL            g_tracking      = NO;   // 4 本指トラッキング中か
static BOOL            g_fired         = NO;   // この 4 本指セッションで既に発火したか
static NSTimeInterval  g_lastFireTs    = 0.0;  // 直近の発火時刻 (クールダウン判定用)

// 4 本指の指移動は NSEventTypeGesture とは別に scrollWheel イベントとしても配送され、
// アプリ (Ghostty/VSCode/Chrome 等) はそちらを見てスクロールしてしまう。gesture を
// 食うだけでは止まらないので、scrollWheel を食う必要がある。2 段階で管理する:
//   g_suppressScroll = 4 本指が今まさに乗っているか (handle_gesture が上げ下げ)
//   g_suppressActive = この 4 本指由来のスクロールシーケンスを抑制中か (慣性が
//                      収束するまで持続。指を離した後の momentum スクロールも食う)
static BOOL            g_suppressScroll = NO;  // 4 本指が乗っている間 YES
static BOOL            g_suppressActive = NO;  // 4 本指由来 scroll シーケンス抑制中
static NSTimeInterval  g_suppressUntil  = 0.0; // 抑制の安全タイムアウト (取りこぼし保険)

// ---- aerospace 実行 ----------------------------------------------------------
//
// fork + exec で aerospace を叩く。SIGCHLD は SIG_IGN にしてあるので
// ゾンビは自動で刈り取られる (待ち合わせ不要)。

static void aerospace_workspace(const char *direction) {
    // "next" / "prev" を渡してワークスペースを切り替える。端では止まる (循環なし)。
    // aerospace v0.20+ は非 TTY からの暗黙 stdin を禁止したため --no-stdin が要る。
    if (fork() == 0) {
        execl(kAerospacePath, "aerospace", "workspace", "--no-stdin", direction, (char *)NULL);
        _exit(127);
    }
}

static void aerospace_focus_monitor(const char *pattern) {
    // monitor-pattern ("secondary" / "built-in" 等) で示したモニターへフォーカスを移す。
    if (fork() == 0) {
        execl(kAerospacePath, "aerospace", "focus-monitor", pattern, (char *)NULL);
        _exit(127);
    }
}

// ---- ジェスチャ判定 ----------------------------------------------------------

// 4 本指スワイプを判定して aerospace を発火する。あわせて g_tracking /
// g_suppressScroll を更新し、4 本指中の scrollWheel 漏れを呼び出し側が食えるようにする。
static void handle_gesture(NSEvent *ev) {
    NSSet<NSTouch *> *all = ev.allTouches;
    if (all.count == 0) return;

    int     count = 0;
    CGFloat sumX = 0.0, sumY = 0.0;
    for (NSTouch *t in all) {
        // 触れている指だけ数える。離れた/キャンセルされた指は無視。
        if (t.phase == NSTouchPhaseEnded || t.phase == NSTouchPhaseCancelled) continue;
        sumX += t.normalizedPosition.x;
        sumY += t.normalizedPosition.y;
        count++;
    }

    if (count != kFingers) {
        // 4 本指が揃っていない (指が乗る前、または離していく途中)。
        // g_suppressScroll は「今 4 本乗っているか」だけを表すので下ろす。ただし
        // g_suppressActive (抑制シーケンス全体) は絶対にここで下ろさない。指を離す
        // 4→3→2→1 の過程と、その後の慣性 scroll まで食い続ける必要があるため。
        // g_suppressActive の解除は scrollWheel 側 (momentum 収束時) だけが行う。
        g_tracking       = NO;
        g_fired          = NO;
        g_suppressScroll = NO;
        return;
    }

    NSTimeInterval ts = ev.timestamp; // monotonic seconds since boot
    CGFloat avgX = sumX / (CGFloat)count;
    CGFloat avgY = sumY / (CGFloat)count;

    if (!g_tracking) {
        // 4 本指が揃った最初のフレーム。ここを基準点にする。
        // この瞬間から「抑制シーケンス」を開始 (g_suppressActive)。以後、指が減って
        // 離れても、慣性 scroll が収束するまで scrollWheel を食い続ける。
        g_tracking       = YES;
        g_fired          = NO;
        g_suppressScroll = YES;
        g_suppressActive = YES;
        g_suppressUntil  = ts + 2.0; // 慣性終了マーカーを取りこぼしても 2 秒で強制解除
        g_startX         = avgX;
        g_startY         = avgY;
        return;
    }

    if (g_fired) return;                              // 1 セッション 1 回だけ発火
    if (ts - g_lastFireTs < kCooldownSec) return;    // クールダウン中

    CGFloat dx = avgX - g_startX;
    CGFloat dy = avgY - g_startY;
    if (fabs(dx) < kSwipeThreshold && fabs(dy) < kSwipeThreshold) return;

    if (fabs(dx) >= fabs(dy)) {
        // 水平優位: 左スワイプ (dx<0) → next、右スワイプ (dx>0) → prev (ナチュラル方向)。
        aerospace_workspace(dx < 0 ? "next" : "prev");
    } else {
        // 垂直優位: NSTouch の normalizedPosition.y は上方向に増える。
        // 上スワイプ (dy>0) → secondary、下スワイプ (dy<0) → built-in。
        // ※ 実機で上下が逆だったら下の三項を入れ替える。
        aerospace_focus_monitor(dy > 0 ? kMonitorUp : kMonitorDown);
    }
    g_fired      = YES;
    g_lastFireTs = ts;
    // スクロール漏れの抑制は g_suppressScroll (4 本指が乗っている間ずっと有効) が担う。
}

// ---- CGEventTap コールバック -------------------------------------------------

static CGEventRef event_callback(CGEventTapProxy proxy, CGEventType type,
                                 CGEventRef event, void *refcon) {
    (void)proxy;

    // タイムアウト / 重い入力で tap が無効化されたら、その場で再有効化する。
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        if (refcon) CGEventTapEnable(*(CFMachPortRef *)refcon, true);
        NSLog(@"[aerospace-swipe-mini] event-tap re-enabled");
        return event;
    }

    if (type == (CGEventType)NSEventTypeGesture) {
        NSEvent *ev = [NSEvent eventWithCGEvent:event];
        if (ev) handle_gesture(ev); // 状態 (g_tracking / g_suppressScroll 等) を更新
        return event; // gesture 自体は素通し。漏れは下の scrollWheel 側で食う
    }

    if (type == kCGEventScrollWheel) {
        // 4 本指の指移動は scrollWheel に化けてアプリ (Ghostty/VSCode/Chrome) に漏れる。
        // これがスクロール漏れの実体。やっかいなのは指を離した後も「慣性スクロール」が
        // 延々と続くこと。実測すると momentumPhase は 1(開始)→2(継続)→3(終了) と遷移し、
        // 指接触中のスクロールは momentumPhase=0。
        //
        // g_suppressActive は 4 本指が一度揃った時点 (handle_gesture) で立ち、ここでは
        // 「シーケンスが続く限り全部食い、慣性終了マーカー momentumPhase=3 で解除」する。
        // 指を離す 4→3→2→1 の過程も慣性も漏れなく食える。通常の 2 本指スクロールは
        // そもそも g_suppressActive が立たないので素通し。
        if (g_suppressActive) {
            // 安全タイムアウト: 慣性終了マーカー (momentum=3) を取りこぼしても、起点から
            // 一定時間でシーケンスを強制終了する。これが無いと万一マーカーを逃したとき
            // 通常スクロールが永久に死ぬ。NSEvent.timestamp と CGEventGetTimestamp は
            // どちらも mach 時間由来 (前者=秒/後者=ナノ秒) なので換算して比較できる。
            NSTimeInterval now = (NSTimeInterval)CGEventGetTimestamp(event) / 1e9;
            int64_t momentum = CGEventGetIntegerValueField(event, kCGScrollWheelEventMomentumPhase);
            if (momentum == 3 || now >= g_suppressUntil) {
                // 慣性終了マーカー or タイムアウト。この 1 発まで食ってシーケンス終了。
                g_suppressActive = NO;
            }
            return NULL;
        }
        // ここに来るのは通常の 2 本指スクロール / マウスホイール。素通し。
    }

    return event; // それ以外は素通し (改変しない)
}

// ---- main --------------------------------------------------------------------

int main(int argc, const char *argv[]) {
    (void)argc; (void)argv;
    signal(SIGCHLD, SIG_IGN); // aerospace 子プロセスを自動刈り取り

    @autoreleasepool {
        // CGEventTap も NSTouch の取得も Accessibility 権限が要る。未許可なら
        // プロンプトを出し、許可されるまで待機する (KeepAlive で再起動されても同様)。
        NSDictionary *opts = @{ (__bridge id)kAXTrustedCheckOptionPrompt: @YES };
        if (!AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts)) {
            NSLog(@"[aerospace-swipe-mini] waiting for Accessibility permission "
                  @"(System Settings > Privacy & Security > Accessibility)...");
            while (!AXIsProcessTrusted()) sleep(1);
        }
        NSLog(@"[aerospace-swipe-mini] Accessibility granted, starting");

        // gesture (ジェスチャ判定用) と scrollWheel (4 本指の漏れスクロールを食う用)。
        CGEventMask mask = CGEventMaskBit(NSEventTypeGesture) |
                           CGEventMaskBit(kCGEventScrollWheel);
        static CFMachPortRef tap; // refcon で再有効化に使うので static
        // default モード (listen-only ではない): 垂直スワイプ発火時に NULL を返して
        // イベントを食えるようにする。横/閾値未満/他ジェスチャは event をそのまま返す。
        tap = CGEventTapCreate(kCGHIDEventTap, kCGHeadInsertEventTap,
                               kCGEventTapOptionDefault, mask, event_callback, &tap);
        if (!tap) {
            fprintf(stderr, "[aerospace-swipe-mini] CGEventTapCreate failed "
                    "(Accessibility permission?)\n");
            return 1;
        }

        CFRunLoopSourceRef src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), src, kCFRunLoopCommonModes);
        CGEventTapEnable(tap, true);

        NSLog(@"[aerospace-swipe-mini] active, %d-finger swipe, threshold=%.2f, cooldown=%.2fs",
              kFingers, kSwipeThreshold, kCooldownSec);

        CFRunLoopRun();
    }
    return 0;
}
