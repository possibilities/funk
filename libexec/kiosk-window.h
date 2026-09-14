#ifndef FUNK_KIOSK_WINDOW_H
#define FUNK_KIOSK_WINDOW_H

#import <AppKit/AppKit.h>

// Public, borderless windows have no system resize/titlebar hit regions.
// Keep these transparent native regions outside the web page's event routing.
typedef NS_OPTIONS(NSUInteger, FunkKioskEdge) {
    FunkKioskEdgeLeft = 1, FunkKioskEdgeRight = 2,
    FunkKioskEdgeBottom = 4, FunkKioskEdgeTop = 8
};
static const CGFloat FunkKioskResizeInset = 6;
static const CGFloat FunkKioskDragHeight = 20;

static FunkKioskEdge kioskResizeEdges(NSPoint point, NSSize size) {
    if (point.x < 0 || point.y < 0 || point.x > size.width || point.y > size.height) return 0;
    FunkKioskEdge edges = 0;
    if (point.x < FunkKioskResizeInset) edges |= FunkKioskEdgeLeft;
    else if (point.x >= size.width - FunkKioskResizeInset) edges |= FunkKioskEdgeRight;
    if (point.y < FunkKioskResizeInset) edges |= FunkKioskEdgeBottom;
    else if (point.y >= size.height - FunkKioskResizeInset) edges |= FunkKioskEdgeTop;
    return edges;
}

static NSRect kioskResizedFrame(NSRect start, NSPoint delta, NSSize minimum, FunkKioskEdge edges) {
    NSRect result = start;
    if (edges & FunkKioskEdgeLeft) {
        result.size.width = MAX(minimum.width, start.size.width - delta.x);
        result.origin.x = NSMaxX(start) - result.size.width;
    } else if (edges & FunkKioskEdgeRight) result.size.width = MAX(minimum.width, start.size.width + delta.x);
    if (edges & FunkKioskEdgeBottom) {
        result.size.height = MAX(minimum.height, start.size.height - delta.y);
        result.origin.y = NSMaxY(start) - result.size.height;
    } else if (edges & FunkKioskEdgeTop) result.size.height = MAX(minimum.height, start.size.height + delta.y);
    return result;
}

static NSPoint kioskScreenPoint(NSEvent *event, NSWindow *window) {
    // Event-global coordinates avoid feeding a previously resized window origin
    // back into queued mouse events. Quartz and AppKit use opposite Y axes.
    CGEventRef cgEvent = event.CGEvent;
    if (cgEvent != NULL) {
        CGPoint point = CGEventGetLocation(cgEvent);
        CGFloat top = NSMaxY(NSScreen.screens.firstObject.frame);
        return NSMakePoint(point.x, top - point.y);
    }
    return [window convertPointToScreen:event.locationInWindow];
}

@interface FunkKioskWindow : NSWindow
@end
@implementation FunkKioskWindow
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }
- (void)performClose:(id)sender {
    // This launcher owns one window. Quit keeps its page alive until the
    // existing asynchronous pagehide/timeout termination handshake completes.
    [NSApp terminate:sender];
}
- (void)performMiniaturize:(id)sender { [self miniaturize:sender]; }
- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(performClose:) || item.action == @selector(performMiniaturize:)) return YES;
    return [super validateMenuItem:item];
}
- (void)setAccessibilityFrame:(NSRect)frame {
    frame.size.width = MAX(self.minSize.width, frame.size.width);
    frame.size.height = MAX(self.minSize.height, frame.size.height);
    [self setFrame:frame display:YES];
}
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
    if (selector == @selector(setAccessibilityFrame:)) return YES;
    return [super isAccessibilitySelectorAllowed:selector];
}
@end

@interface FunkKioskContentView : NSView
@end
@implementation FunkKioskContentView
- (NSView *)hitTest:(NSPoint)point {
    NSPoint local = [self convertPoint:point fromView:self.superview];
    if (NSPointInRect(local, self.bounds) &&
        (kioskResizeEdges(local, self.bounds.size) || local.y >= NSMaxY(self.bounds) - FunkKioskDragHeight)) return self;
    return [super hitTest:point];
}
- (BOOL)acceptsFirstMouse:(NSEvent *)event { (void)event; return YES; }
- (void)resetCursorRects {
    [super resetCursorRects];
    CGFloat width = NSWidth(self.bounds), height = NSHeight(self.bounds), edge = FunkKioskResizeInset;
    [self addCursorRect:NSMakeRect(edge, height - FunkKioskDragHeight, width - 2 * edge, FunkKioskDragHeight - edge)
                 cursor:NSCursor.openHandCursor];
    [self addCursorRect:NSMakeRect(0, edge, edge, height - 2 * edge) cursor:NSCursor.resizeLeftRightCursor];
    [self addCursorRect:NSMakeRect(width - edge, edge, edge, height - 2 * edge) cursor:NSCursor.resizeLeftRightCursor];
    [self addCursorRect:NSMakeRect(edge, 0, width - 2 * edge, edge) cursor:NSCursor.resizeUpDownCursor];
    [self addCursorRect:NSMakeRect(edge, height - edge, width - 2 * edge, edge) cursor:NSCursor.resizeUpDownCursor];
    for (NSNumber *x in @[@0, @(width - edge)]) for (NSNumber *y in @[@0, @(height - edge)]) {
        NSCursor *cursor = NSCursor.crosshairCursor;
        if (@available(macOS 15.0, *)) {
            NSCursorFrameResizePosition position = (x.doubleValue == 0 ? NSCursorFrameResizePositionLeft : NSCursorFrameResizePositionRight)
                | (y.doubleValue == 0 ? NSCursorFrameResizePositionBottom : NSCursorFrameResizePositionTop);
            cursor = [NSCursor frameResizeCursorFromPosition:position inDirections:NSCursorFrameResizeDirectionsAll];
        }
        [self addCursorRect:NSMakeRect(x.doubleValue, y.doubleValue, edge, edge) cursor:cursor];
    }
}
- (void)mouseDown:(NSEvent *)event {
    NSWindow *window = self.window;
    NSPoint local = [self convertPoint:event.locationInWindow fromView:nil];
    FunkKioskEdge edges = kioskResizeEdges(local, self.bounds.size);
    [window makeKeyWindow];
    if (!edges) {
        [window performWindowDragWithEvent:event];
        return;
    }
    NSRect start = window.frame;
    NSPoint origin = kioskScreenPoint(event, window);
    [self viewWillStartLiveResize];
    while (window.visible && window.keyWindow && NSApp.active) {
        NSEvent *next = [NSApp nextEventMatchingMask:NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp | NSEventMaskAppKitDefined
            untilDate:[NSDate dateWithTimeIntervalSinceNow:0.1] inMode:NSEventTrackingRunLoopMode dequeue:YES];
        if (next == nil) continue;
        if (next.type == NSEventTypeLeftMouseUp) break;
        if (next.type != NSEventTypeLeftMouseDragged) { [NSApp sendEvent:next]; continue; }
        NSPoint point = kioskScreenPoint(next, window);
        NSRect frame = kioskResizedFrame(start, NSMakePoint(point.x - origin.x, point.y - origin.y), window.minSize, edges);
        [window setFrame:frame display:YES];
    }
    [self viewDidEndLiveResize];
    [window invalidateCursorRectsForView:self];
}
@end
#endif
