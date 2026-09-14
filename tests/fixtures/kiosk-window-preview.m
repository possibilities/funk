// Explicitly launched only under a desktop resource lease. Uses the production
// window/menu/termination implementation with local HTML and an isolated bundle.
#define main FunkKioskProductionMain
#import "../../libexec/kiosk-launcher.m"
#undef main

@interface FunkKioskPreviewDelegate : FunkKioskDelegate
@end
@implementation FunkKioskPreviewDelegate
- (void)loadLauncherURL:(NSURL *)url {
    (void)url;
    [self.webView loadHTMLString:@"<!doctype html><meta charset='utf-8'>"
        "<style>html{background:#202020;color:#eee;font:18px system-ui}body{margin:28px}"
        "textarea{font:20px system-ui;width:90%;height:150px;background:#333;color:white}"
        "button{font:18px system-ui;margin-top:16px;padding:8px}</style>"
        "<h1>Funk square-window test</h1><p>Disposable local page. No live app data.</p>"
        "<p>Drag the top edge below its resize strip. Resize any edge or corner.</p>"
        "<textarea aria-label='Test composer' placeholder='Type and test Undo, Paste, selection'></textarea>"
        "<p id='result'>Button untouched</p><button onclick=\"document.querySelector('#result').textContent='Button works'\">Test button</button>"
        "<script>window.addEventListener('pagehide',()=>localStorage.setItem('closed','flushed'))</script>"
        baseURL:[NSURL URLWithString:@"https://funk-square-window-test.invalid/"]];
}
@end

int main(void) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        installMainMenu();
        FunkKioskPreviewDelegate *delegate = [[FunkKioskPreviewDelegate alloc] init];
        application.delegate = delegate;
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        [application run];
    }
    return 0;
}
