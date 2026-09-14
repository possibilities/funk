#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

#import "kiosk-webview-support.h"

#include <stdio.h>

@interface StorageHarnessDelegate : NSObject <NSApplicationDelegate, WKNavigationDelegate>

@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, strong) NSURL *url;
@property(nonatomic, copy) NSString *script;
@property(nonatomic) NSTimeInterval drainDelay;
@property(nonatomic) BOOL abruptExit;
@property(nonatomic) BOOL finished;
@property(nonatomic) BOOL terminationPending;

@end

@implementation StorageHarnessDelegate

- (void)finishWithResult:(id)result error:(NSError *)error {
    if (self.finished) {
        return;
    }
    self.finished = YES;

    NSMutableDictionary *output = [NSMutableDictionary dictionaryWithDictionary:@{
        @"bundleIdentifier": NSBundle.mainBundle.bundleIdentifier ?: @"",
        @"persistentDataStore": @(self.webView.configuration.websiteDataStore.isPersistent),
        @"url": self.webView.URL.absoluteString ?: self.url.absoluteString ?: @"",
    }];
    if (error != nil) {
        output[@"error"] = error.localizedDescription;
    } else {
        output[@"result"] = result ?: NSNull.null;
    }

    NSData *data = [NSJSONSerialization dataWithJSONObject:output options:0 error:nil];
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(self.drainDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (self.abruptExit) {
            _exit(error == nil ? 0 : 1);
        }
        [NSApp terminate:nil];
    });
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;

    NSRect frame = NSMakeRect(-10000, -10000, 800, 600);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:NSWindowStyleMaskBorderless
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configureKioskWebView(configuration);
    self.webView = [[WKWebView alloc] initWithFrame:frame configuration:configuration];
    self.webView.navigationDelegate = self;
    self.window.contentView = self.webView;
    [self.window orderOut:nil];
    [self.webView loadRequest:[NSURLRequest requestWithURL:self.url]];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        NSError *timeout = [NSError errorWithDomain:@"FunkStorageHarness"
                                                code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"navigation timed out"}];
        [self finishWithResult:nil error:timeout];
    });
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    (void)navigation;
    [webView callAsyncJavaScript:self.script
                      arguments:@{}
                        inFrame:nil
                 inContentWorld:WKContentWorld.pageWorld
              completionHandler:^(id result, NSError *error) {
        [self finishWithResult:result error:error];
    }];
}

- (void)webView:(WKWebView *)webView
    didFailProvisionalNavigation:(WKNavigation *)navigation
                       withError:(NSError *)error {
    (void)webView;
    (void)navigation;
    [self finishWithResult:nil error:error];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    return requestPageHideBeforeTermination(
        self.webView, sender, &_terminationPending
    );
}

@end

static void usage(void) {
    fprintf(stderr,
            "usage: kiosk-storage-harness URL SCRIPT_FILE DRAIN_MILLISECONDS graceful|abrupt\n");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 5) {
            usage();
            return 64;
        }

        NSURL *url = [NSURL URLWithString:[NSString stringWithUTF8String:argv[1]]];
        NSString *scriptPath = [NSString stringWithUTF8String:argv[2]];
        NSString *script = [NSString stringWithContentsOfFile:scriptPath
                                                      encoding:NSUTF8StringEncoding
                                                         error:nil];
        NSScanner *scanner = [NSScanner scannerWithString:[NSString stringWithUTF8String:argv[3]]];
        double drainMilliseconds = 0;
        BOOL validDelay = [scanner scanDouble:&drainMilliseconds] && scanner.isAtEnd &&
            drainMilliseconds >= 0;
        NSString *exitMode = [NSString stringWithUTF8String:argv[4]];
        if (url == nil || script == nil || !validDelay ||
            (! [exitMode isEqualToString:@"graceful"] &&
             ! [exitMode isEqualToString:@"abrupt"])) {
            usage();
            return 64;
        }

        NSApplication *application = NSApplication.sharedApplication;
        [application setActivationPolicy:NSApplicationActivationPolicyProhibited];
        StorageHarnessDelegate *delegate = [[StorageHarnessDelegate alloc] init];
        delegate.url = url;
        delegate.script = script;
        delegate.drainDelay = drainMilliseconds / 1000.0;
        delegate.abruptExit = [exitMode isEqualToString:@"abrupt"];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
