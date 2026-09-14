#import "kiosk-window.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        [application setActivationPolicy:NSApplicationActivationPolicyProhibited];
        NSRect start = NSMakeRect(-900, 100, 1000, 700);
        NSSize minimum = NSMakeSize(640, 400);
        for (NSNumber *edge in @[@1, @2, @4, @8, @5, @9, @6, @10]) {
            FunkKioskEdge selected = edge.unsignedIntegerValue;
            for (NSNumber *delta in @[@(-10000), @(-200), @0, @200, @10000]) {
                NSPoint travel = NSMakePoint(delta.doubleValue, delta.doubleValue);
                NSRect result = kioskResizedFrame(start, travel, minimum, selected);
                assert(result.size.width >= minimum.width && result.size.height >= minimum.height);
                if (selected & FunkKioskEdgeLeft) assert(NSMaxX(result) == NSMaxX(start));
                else assert(NSMinX(result) == NSMinX(start));
                if (selected & FunkKioskEdgeBottom) assert(NSMaxY(result) == NSMaxY(start));
                else assert(NSMinY(result) == NSMinY(start));
                // Repeated queued pointer positions must not accumulate movement.
                assert(NSEqualRects(result, kioskResizedFrame(start, travel, minimum, selected)));
                assert(NSEqualRects(start, kioskResizedFrame(start, NSZeroPoint, minimum, selected)));
            }
        }
        assert(kioskResizeEdges(NSMakePoint(1, 1), start.size) == (FunkKioskEdgeLeft | FunkKioskEdgeBottom));
        assert(kioskResizeEdges(NSMakePoint(999, 699), start.size) == (FunkKioskEdgeRight | FunkKioskEdgeTop));
        assert(kioskResizeEdges(NSMakePoint(500, 699), start.size) == FunkKioskEdgeTop);
        assert(kioskResizeEdges(NSMakePoint(500, 350), start.size) == 0);
        assert(kioskResizeEdges(NSMakePoint(-1, 350), start.size) == 0);

        FunkKioskWindow *window = [[FunkKioskWindow alloc] initWithContentRect:start
            styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:YES];
        window.releasedWhenClosed = NO;
        window.minSize = minimum;
        window.opaque = YES;
        window.hasShadow = YES;
        window.collectionBehavior = NSWindowCollectionBehaviorFullScreenNone;
        FunkKioskContentView *content = [[FunkKioskContentView alloc] initWithFrame:NSMakeRect(0, 0, 1000, 700)];
        window.contentView = content;
        NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(30, 30, 300, 40)];
        [content addSubview:field];
        assert(window.canBecomeKeyWindow && window.canBecomeMainWindow);
        assert(NSEqualRects(window.frame, start));
        assert([window makeFirstResponder:field]);
        NSView *hit = [content hitTest:NSMakePoint(100, 50)];
        assert(hit == field || hit == window.firstResponder);
        assert([content hitTest:NSMakePoint(500, 690)] == content);
        assert([content hitTest:NSMakePoint(2, 350)] == content);
        assert([window validateMenuItem:[[NSMenuItem alloc] initWithTitle:@"Close" action:@selector(performClose:) keyEquivalent:@"w"]]);
        assert([window isAccessibilitySelectorAllowed:@selector(setAccessibilityFrame:)]);
        [window setAccessibilityFrame:NSMakeRect(-1200, 90, 20, 20)];
        assert(NSEqualSizes(window.frame.size, minimum));
        assert(window.frame.origin.x == -1200 && window.frame.origin.y == 90);
        assert(!window.visible);
        printf("Kiosk window geometry, hit regions, focus eligibility, Close validation and accessibility frame tests passed (no visible window).\n");
    }
    return 0;
}
