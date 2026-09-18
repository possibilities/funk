#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

#import "kiosk-find-controller.h"

static BOOL waitForStatus(FunkKioskFindController *controller, NSString *status) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (![controller.findStatusText isEqualToString:status]) {
        if (deadline.timeIntervalSinceNow <= 0) return NO;
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return YES;
}

@interface KioskFindHarness : NSObject <WKNavigationDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, strong) FunkKioskFindController *findController;
@end

@implementation KioskFindHarness

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    (void)webView;
    (void)navigation;
    [self.findController showFindPanel:nil];
    NSCAssert(self.findController.findPanelVisible, @"Find panel was not visible");

    self.findController.searchString = @"needle";
    [self.findController findNext:nil];
    NSCAssert(waitForStatus(self.findController, @"Match found"),
              @"Find Next did not find page content");
    [self.findController findPrevious:nil];
    NSCAssert(waitForStatus(self.findController, @"Match found"),
              @"Find Previous did not find page content");

    self.findController.searchString = @"absent";
    [self.findController findNext:nil];
    NSCAssert(waitForStatus(self.findController, @"No matches"),
              @"Find did not report an absent string");
    [self.findController dismissFindPanel:nil];
    NSCAssert(!self.findController.findPanelVisible, @"Find panel did not dismiss");
    printf("Kiosk native Find panel searches WKWebView content and dismisses successfully.\n");
    [NSApp terminate:nil];
}

@end

int main(void) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        KioskFindHarness *harness = [[KioskFindHarness alloc] init];
        harness.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 400)
                                                     styleMask:NSWindowStyleMaskTitled
                                                       backing:NSBackingStoreBuffered
                                                         defer:NO];
        harness.webView = [[WKWebView alloc] initWithFrame:harness.window.contentView.bounds];
        harness.webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        harness.webView.navigationDelegate = harness;
        [harness.window.contentView addSubview:harness.webView];
        harness.findController = [[FunkKioskFindController alloc] init];
        harness.findController.webView = harness.webView;
        [harness.window makeKeyAndOrderFront:nil];
        [harness.webView loadHTMLString:@"<p>needle one</p><p>needle two</p>"
                                  baseURL:[NSURL URLWithString:@"https://find-harness.localhost/"]];
        [application run];
    }
    return 0;
}
