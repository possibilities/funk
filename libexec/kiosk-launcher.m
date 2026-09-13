#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

#include <stdio.h>
#include <string.h>

static NSURL *launcherURL(void) {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"launcher-url"
                                                     ofType:nil];
    NSString *value = [NSString stringWithContentsOfFile:path ?: @""
                                                 encoding:NSUTF8StringEncoding
                                                    error:nil];
    value = [value stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSURL *url = [NSURL URLWithString:value ?: @""];
    if (url == nil || ![url.scheme isEqualToString:@"https"] || url.host.length == 0) {
        return nil;
    }
    return url;
}

@interface FunkKioskDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>

@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) WKWebView *webView;

@end

@implementation FunkKioskDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;

    NSURL *url = launcherURL();
    if (url == nil) {
        NSLog(@"Funk kiosk launcher has an invalid URL resource");
        [NSApp terminate:nil];
        return;
    }

    NSRect frame = NSMakeRect(0, 0, 1280, 800);
    NSWindowStyleMask style = NSWindowStyleMaskTitled |
        NSWindowStyleMaskClosable |
        NSWindowStyleMaskMiniaturizable |
        NSWindowStyleMaskResizable |
        NSWindowStyleMaskFullSizeContentView;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:style
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.delegate = self;
    window.title = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: @"";
    window.titleVisibility = NSWindowTitleHidden;
    window.titlebarAppearsTransparent = YES;
    window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
    window.collectionBehavior = NSWindowCollectionBehaviorFullScreenNone;
    window.backgroundColor = NSColor.blackColor;
    window.minSize = NSMakeSize(640, 400);
    for (NSNumber *buttonType in @[
        @(NSWindowCloseButton), @(NSWindowMiniaturizeButton), @(NSWindowZoomButton)
    ]) {
        [[window standardWindowButton:buttonType.unsignedIntegerValue] setHidden:YES];
    }

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.websiteDataStore = WKWebsiteDataStore.defaultDataStore;
    WKWebView *webView = [[WKWebView alloc] initWithFrame:frame
                                           configuration:configuration];
    webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    window.contentView = webView;
    self.window = window;
    self.webView = webView;

    NSString *autosaveName = [NSString stringWithFormat:@"%@.main-window",
        NSBundle.mainBundle.bundleIdentifier ?: @"com.arthack.funk.kiosk"];
    if (![window setFrameUsingName:autosaveName]) {
        [window center];
    }
    [window setFrameAutosaveName:autosaveName];
    [webView loadRequest:[NSURLRequest requestWithURL:url]];
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "--check") == 0) {
            NSURL *url = launcherURL();
            if (url == nil) {
                return 65;
            }
            printf("url=%s\nwindow=chromeless\nfullscreen=disabled\nengine=WKWebView\n",
                   url.absoluteString.UTF8String);
            return 0;
        }
        if (argc > 1 && strncmp(argv[1], "-psn_", 5) != 0) {
            return 64;
        }
        NSApplication *application = NSApplication.sharedApplication;
        FunkKioskDelegate *delegate = [[FunkKioskDelegate alloc] init];
        application.delegate = delegate;
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        [application run];
    }
    return 0;
}
