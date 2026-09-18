#ifndef FUNK_KIOSK_FIND_CONTROLLER_H
#define FUNK_KIOSK_FIND_CONTROLLER_H

#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

@interface FunkKioskFindController : NSObject <NSSearchFieldDelegate>

@property(nonatomic, weak) WKWebView *webView;
@property(nonatomic, copy) NSString *searchString;
@property(nonatomic, readonly) BOOL findPanelVisible;
@property(nonatomic, readonly, copy) NSString *findStatusText;

- (void)showFindPanel:(id)sender;
- (void)findNext:(id)sender;
- (void)findPrevious:(id)sender;
- (void)dismissFindPanel:(id)sender;

@end

@implementation FunkKioskFindController {
    NSPanel *_panel;
    NSSearchField *_searchField;
    NSTextField *_statusLabel;
}

- (void)ensureFindPanel {
    if (_panel != nil) {
        return;
    }

    _panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 480, 72)
                                        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskUtilityWindow
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
    _panel.title = @"Find";
    _panel.floatingPanel = YES;
    _panel.hidesOnDeactivate = NO;
    _panel.releasedWhenClosed = NO;

    NSView *content = _panel.contentView;
    _searchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(16, 36, 190, 24)];
    _searchField.placeholderString = @"Find in page";
    _searchField.sendsSearchStringImmediately = YES;
    _searchField.target = self;
    _searchField.action = @selector(findNext:);
    _searchField.delegate = self;
    [content addSubview:_searchField];

    NSButton *previous = [NSButton buttonWithTitle:@"Previous"
                                             target:self
                                             action:@selector(findPrevious:)];
    previous.frame = NSMakeRect(214, 36, 82, 24);
    [content addSubview:previous];

    NSButton *next = [NSButton buttonWithTitle:@"Next"
                                         target:self
                                         action:@selector(findNext:)];
    next.frame = NSMakeRect(302, 36, 58, 24);
    [content addSubview:next];

    NSButton *done = [NSButton buttonWithTitle:@"Done"
                                         target:self
                                         action:@selector(dismissFindPanel:)];
    done.frame = NSMakeRect(368, 36, 64, 24);
    done.keyEquivalent = @"\e";
    [content addSubview:done];

    _statusLabel = [NSTextField labelWithString:@"Type to find"];
    _statusLabel.frame = NSMakeRect(16, 12, 448, 17);
    [content addSubview:_statusLabel];
}

- (void)showFindPanel:(id)sender {
    (void)sender;
    [self ensureFindPanel];
    NSWindow *parent = self.webView.window;
    if (parent != nil && _panel.parentWindow != parent) {
        [_panel.parentWindow removeChildWindow:_panel];
        [parent addChildWindow:_panel ordered:NSWindowAbove];
    }
    [_panel center];
    [_panel makeKeyAndOrderFront:nil];
    [_panel makeFirstResponder:_searchField];
    [_searchField selectText:nil];
}

- (void)findNext:(id)sender {
    (void)sender;
    [self findBackwards:NO];
}

- (void)findPrevious:(id)sender {
    (void)sender;
    [self findBackwards:YES];
}

- (void)findBackwards:(BOOL)backwards {
    NSString *query = _searchField.stringValue;
    if (query.length == 0) {
        _statusLabel.stringValue = @"Type to find";
        return;
    }
    WKWebView *webView = self.webView;
    if (webView == nil) {
        _statusLabel.stringValue = @"Page is not ready";
        return;
    }
    WKFindConfiguration *configuration = [[WKFindConfiguration alloc] init];
    configuration.backwards = backwards;
    configuration.wraps = YES;
    _statusLabel.stringValue = @"Searching…";
    __weak FunkKioskFindController *weakSelf = self;
    [webView findString:query withConfiguration:configuration completionHandler:^(WKFindResult *result) {
        FunkKioskFindController *self = weakSelf;
        if (self == nil || ![self->_searchField.stringValue isEqualToString:query]) {
            return;
        }
        self->_statusLabel.stringValue = result.matchFound ? @"Match found" : @"No matches";
    }];
}

- (void)dismissFindPanel:(id)sender {
    (void)sender;
    [_panel orderOut:nil];
    [_panel.parentWindow removeChildWindow:_panel];
    [self.webView.window makeKeyAndOrderFront:nil];
}

- (void)controlTextDidChange:(NSNotification *)notification {
    (void)notification;
    [self findNext:nil];
}

- (NSString *)searchString {
    [self ensureFindPanel];
    return _searchField.stringValue;
}

- (void)setSearchString:(NSString *)searchString {
    [self ensureFindPanel];
    _searchField.stringValue = searchString ?: @"";
}

- (BOOL)findPanelVisible {
    return _panel.isVisible;
}

- (NSString *)findStatusText {
    return _statusLabel.stringValue ?: @"";
}

@end

#endif
