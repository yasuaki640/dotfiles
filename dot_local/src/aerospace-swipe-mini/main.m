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
// gesture イベントだけを listen し、scrollWheel には一切触れない。4 本指の指移動は
// gesture とは別に scrollWheel としてもアプリに配送されるため、4 本スワイプの瞬間に
// Ghostty/Chrome 等が一瞬スクロールするが、これは許容する。以前は scrollWheel も tap
// して 4 本指由来の漏れを食っていたが、2 本指スクロールも tap を経由する分だけ起動に
// ラグが出る実害があったため撤去した。
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
// 軸判定のドミナンス比。優位軸が劣位軸のこの倍率以上 (物理距離換算で) 動いて
// いなければ発火しない。斜め成分のあるスワイプを誤った軸で発火させないため。
// 3.0 = 軸から約 ±18° 以内のスワイプだけ受け付ける (2.0 では誤爆が残った)。
static const double kAxisDominance  = 3.0;
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

// 4 本指スワイプを判定して aerospace を発火する。
static void handle_gesture(NSEvent *ev) {
    NSSet<NSTouch *> *all = ev.allTouches;
    if (all.count == 0) return;

    int     count = 0;
    CGFloat sumX = 0.0, sumY = 0.0;
    NSSize  devSize = NSZeroSize; // トラックパッドの物理サイズ (アスペクト補正用)
    for (NSTouch *t in all) {
        // 触れている指だけ数える。離れた/キャンセルされた指は無視。
        if (t.phase == NSTouchPhaseEnded || t.phase == NSTouchPhaseCancelled) continue;
        sumX += t.normalizedPosition.x;
        sumY += t.normalizedPosition.y;
        devSize = t.deviceSize;
        count++;
    }

    if (count != kFingers) {
        // 4 本指が揃っていない (指が乗る前、または離していく途中)。トラッキングを下ろす。
        // g_fired は全指が離れるまで下ろさない: スワイプ中に一瞬 4 本未満と報告される
        // ことがあり、ここで毎回リセットすると同一ジェスチャ内で二度撃ちする。
        g_tracking = NO;
        if (count == 0) g_fired = NO;
        return;
    }

    NSTimeInterval ts = ev.timestamp; // monotonic seconds since boot
    CGFloat avgX = sumX / (CGFloat)count;
    CGFloat avgY = sumY / (CGFloat)count;

    if (!g_tracking) {
        // 4 本指が揃った最初のフレーム。ここを基準点にする。
        // (g_fired はここでは触らない: 全指リフトで初めて再武装する)
        g_tracking = YES;
        g_startX   = avgX;
        g_startY   = avgY;
        return;
    }

    if (g_fired) return;                              // 1 セッション 1 回だけ発火
    if (ts - g_lastFireTs < kCooldownSec) return;    // クールダウン中

    CGFloat dx = avgX - g_startX;
    CGFloat dy = avgY - g_startY;
    if (fabs(dx) < kSwipeThreshold && fabs(dy) < kSwipeThreshold) return;

    // normalizedPosition はパッドの縦横それぞれで 0〜1 に正規化されるため、横長の
    // トラックパッドでは同じ物理移動量でも y の方が大きく出る。deviceSize で物理
    // 距離比に直してから軸の優劣を判定する (横スワイプのわずかな縦ドリフトが
    // focus-monitor として誤爆するのを防ぐ)。
    CGFloat pdx = fabs(dx) * (devSize.width  > 0 ? devSize.width  : 1.0);
    CGFloat pdy = fabs(dy) * (devSize.height > 0 ? devSize.height : 1.0);

    if (pdx >= pdy * kAxisDominance) {
        // 水平優位: 左スワイプ (dx<0) → next、右スワイプ (dx>0) → prev (ナチュラル方向)。
        aerospace_workspace(dx < 0 ? "next" : "prev");
    } else if (pdy >= pdx * kAxisDominance) {
        // 垂直優位: NSTouch の normalizedPosition.y は上方向に増える。
        // 上スワイプ (dy>0) → secondary、下スワイプ (dy<0) → built-in。
        aerospace_focus_monitor(dy > 0 ? kMonitorUp : kMonitorDown);
    } else {
        // どちらの軸も優位でない斜めスワイプ。発火せず、指がさらに動いて
        // どちらかが優位になるのを待つ (誤った軸で発火するよりは無発火がまし)。
        return;
    }
    g_fired      = YES;
    g_lastFireTs = ts;
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
        if (ev) handle_gesture(ev); // 状態 (g_tracking) を更新して必要なら aerospace を発火
        return event; // gesture 自体は素通し
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

        // gesture (ジェスチャ判定用) だけを listen する。scrollWheel は触らない。
        CGEventMask mask = CGEventMaskBit(NSEventTypeGesture);
        static CFMachPortRef tap; // refcon で再有効化に使うので static
        // listen-only モード: イベントを食う必要がない (gesture は素通し、scrollWheel は
        // そもそも tap しない) ので listenOnly にして 2 本指スクロール等への干渉をゼロにする。
        tap = CGEventTapCreate(kCGHIDEventTap, kCGHeadInsertEventTap,
                               kCGEventTapOptionListenOnly, mask, event_callback, &tap);
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
