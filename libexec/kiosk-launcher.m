#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

#import "kiosk-webview-support.h"
#import "kiosk-window.h"

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
@property(nonatomic) BOOL terminationPending;

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
    FunkKioskWindow *window = [[FunkKioskWindow alloc] initWithContentRect:frame
                                                   styleMask:NSWindowStyleMaskBorderless
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.releasedWhenClosed = NO;
    window.opaque = YES;
    window.hasShadow = YES;
    window.delegate = self;
    window.title = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: @"";
    window.collectionBehavior = NSWindowCollectionBehaviorFullScreenNone;
    window.backgroundColor = NSColor.blackColor;
    window.minSize = NSMakeSize(640, 400);
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configureKioskWebView(configuration);
    WKWebView *webView = [[WKWebView alloc] initWithFrame:frame
                                           configuration:configuration];
    webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    FunkKioskContentView *content = [[FunkKioskContentView alloc] initWithFrame:frame];
    window.contentView = content;
    webView.frame = content.bounds;
    [content addSubview:webView];
    window.accessibilityRole = NSAccessibilityWindowRole;
    window.accessibilitySubrole = NSAccessibilityStandardWindowSubrole;
    __weak FunkKioskWindow *weakWindow = window;
    window.accessibilityCustomActions = @[
        [[NSAccessibilityCustomAction alloc] initWithName:@"Close window" handler:^BOOL {
            [weakWindow performClose:nil]; return YES;
        }],
        [[NSAccessibilityCustomAction alloc] initWithName:@"Minimize window" handler:^BOOL {
            [weakWindow performMiniaturize:nil]; return YES;
        }]
    ];
    self.window = window;
    self.webView = webView;

    NSString *autosaveName = [NSString stringWithFormat:@"%@.main-window",
        NSBundle.mainBundle.bundleIdentifier ?: @"com.arthack.funk.kiosk"];
    if (![window setFrameUsingName:autosaveName]) {
        [window center];
    }
    [window setFrameAutosaveName:autosaveName];
    [self loadLauncherURL:url];
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)loadLauncherURL:(NSURL *)url {
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    return requestPageHideBeforeTermination(
        self.webView, sender, &_terminationPending
    );
}

@end

static NSMenu *newMainMenu(void) {
    NSMenu *mainMenu = [[NSMenu alloc] init];

    NSMenuItem *applicationItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:applicationItem];
    NSMenu *applicationMenu = [[NSMenu alloc] init];
    NSString *appName = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: @"App";
    NSMenuItem *quitItem = [[NSMenuItem alloc]
        initWithTitle:[NSString stringWithFormat:@"Quit %@", appName]
               action:@selector(terminate:)
        keyEquivalent:@"q"];
    [applicationMenu addItem:quitItem];
    applicationItem.submenu = applicationMenu;

    NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:@"Edit"
                                                     action:nil
                                              keyEquivalent:@""];
    [mainMenu addItem:editItem];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    NSArray<NSMenuItem *> *editItems = @[
        [[NSMenuItem alloc] initWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"],
        [[NSMenuItem alloc] initWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"z"],
        NSMenuItem.separatorItem,
        [[NSMenuItem alloc] initWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"],
        [[NSMenuItem alloc] initWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"],
        [[NSMenuItem alloc] initWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"],
        NSMenuItem.separatorItem,
        [[NSMenuItem alloc] initWithTitle:@"Select All"
                                  action:@selector(selectAll:)
                           keyEquivalent:@"a"],
    ];
    editItems[1].keyEquivalentModifierMask =
        NSEventModifierFlagCommand | NSEventModifierFlagShift;
    for (NSMenuItem *item in editItems) {
        if (!item.isSeparatorItem) {
            item.target = nil;
            if (item != editItems[1]) {
                item.keyEquivalentModifierMask = NSEventModifierFlagCommand;
            }
        }
        [editMenu addItem:item];
    }
    editItem.submenu = editMenu;

    NSMenuItem *windowItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:windowItem];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    NSMenuItem *closeItem = [[NSMenuItem alloc] initWithTitle:@"Close"
                                                      action:@selector(performClose:)
                                               keyEquivalent:@"w"];
    [windowMenu addItem:closeItem];
    windowItem.submenu = windowMenu;
    return mainMenu;
}

static void installMainMenu(void) {
    NSMenu *mainMenu = newMainMenu();
    NSApp.windowsMenu = mainMenu.itemArray.lastObject.submenu;
    NSApp.mainMenu = mainMenu;
}

static void printEditMenuCheck(void) {
    NSMenu *editMenu = newMainMenu().itemArray[1].submenu;
    for (NSMenuItem *item in editMenu.itemArray) {
        if (item.isSeparatorItem) {
            continue;
        }
        NSEventModifierFlags modifiers = item.keyEquivalentModifierMask &
            NSEventModifierFlagDeviceIndependentFlagsMask;
        NSString *modifierName = modifiers == NSEventModifierFlagCommand
            ? @"command"
            : modifiers == (NSEventModifierFlagCommand | NSEventModifierFlagShift)
                ? @"command+shift"
                : @"other";
        printf("edit=%s|selector=%s|key=%s|modifiers=%s|target=%s\n",
               item.title.UTF8String,
               NSStringFromSelector(item.action).UTF8String,
               item.keyEquivalent.UTF8String,
               modifierName.UTF8String,
               item.target == nil ? "responder-chain" : "explicit");
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "--check") == 0) {
            NSURL *url = launcherURL();
            if (url == nil) {
                return 65;
            }
            printf("url=%s\nwindow=chromeless\nfullscreen=disabled\nengine=WKWebView\n",
                   url.absoluteString.UTF8String);
            printf("corners=square\nwindow-drag=top-20pt\nwindow-resize=outer-6pt\n");
            printf("termination=pagehide-with-500ms-timeout\n");
            printf("persistence-instance=%s\n",
                   persistenceInstanceIdentifier().UTF8String);
            printEditMenuCheck();
            return 0;
        }
        if (argc > 1 && strncmp(argv[1], "-psn_", 5) != 0) {
            return 64;
        }
        NSApplication *application = NSApplication.sharedApplication;
        installMainMenu();
        FunkKioskDelegate *delegate = [[FunkKioskDelegate alloc] init];
        application.delegate = delegate;
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        [application run];
    }
    return 0;
}
