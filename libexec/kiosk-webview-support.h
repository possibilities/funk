#ifndef FUNK_KIOSK_WEBVIEW_SUPPORT_H
#define FUNK_KIOSK_WEBVIEW_SUPPORT_H

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

static NSString *persistenceInstanceIdentifier(void) {
    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier ?: @"com.arthack.funk.kiosk";
    return [bundleIdentifier stringByAppendingString:@":main"];
}

static WKUserScript *persistenceInstanceScript(void) {
    NSData *encodedIdentifier = [NSJSONSerialization
        dataWithJSONObject:persistenceInstanceIdentifier()
                   options:NSJSONWritingFragmentsAllowed
                     error:nil];
    NSString *jsonIdentifier = [[NSString alloc] initWithData:encodedIdentifier
                                                     encoding:NSUTF8StringEncoding];
    NSString *source = [NSString stringWithFormat:
        @"Object.defineProperty(window, 'funkKiosk', { value: Object.freeze({ "
         "persistenceInstanceId: %@ }), writable: false, configurable: false });",
        jsonIdentifier];
    return [[WKUserScript alloc] initWithSource:source
                                  injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                               forMainFrameOnly:YES];
}

static void configureKioskWebView(WKWebViewConfiguration *configuration) {
    configuration.websiteDataStore = WKWebsiteDataStore.defaultDataStore;
    [configuration.userContentController addUserScript:persistenceInstanceScript()];
}

static NSApplicationTerminateReply requestPageHideBeforeTermination(
    WKWebView *webView,
    NSApplication *application,
    BOOL *terminationPending
) {
    if (webView == nil) {
        return NSTerminateNow;
    }
    if (*terminationPending) {
        return NSTerminateLater;
    }
    *terminationPending = YES;

    __block BOOL replied = NO;
    void (^finishTermination)(void) = ^{
        if (replied) {
            return;
        }
        replied = YES;
        [application replyToApplicationShouldTerminate:YES];
    };
    NSString *pageHideScript =
        @"window.dispatchEvent(typeof PageTransitionEvent === 'function' "
         "? new PageTransitionEvent('pagehide', { persisted: false }) "
         ": new Event('pagehide'));";
    [webView evaluateJavaScript:pageHideScript
              completionHandler:^(id result, NSError *error) {
        (void)result;
        (void)error;
        finishTermination();
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), finishTermination);
    return NSTerminateLater;
}

#endif
