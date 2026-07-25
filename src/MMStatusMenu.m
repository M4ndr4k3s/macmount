//
//  MMStatusMenu.m
//

#import "MMStatusMenu.h"

#import "MMCoordinator.h"
#import "MMMainWindow.h"
#import "MMShare.h"
#import "MMStore.h"

@interface MMStatusMenu () <NSMenuDelegate>
@property (nonatomic, strong) NSStatusItem *statusItem;
@end

@implementation MMStatusMenu

- (void)install {
    if (self.statusItem != nil) return;

    self.statusItem = [[NSStatusBar systemStatusBar]
        statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.image = [self statusImage];
    self.statusItem.button.toolTip = NSLocalizedString(@"app.name", @"MacMount");

    NSMenu *menu = [[NSMenu alloc] init];
    menu.delegate = self;
    // Sem isso o AppKit ignora o -enabled que definimos por item.
    menu.autoenablesItems = NO;
    self.statusItem.menu = menu;
}

- (void)remove {
    if (self.statusItem == nil) return;
    [[NSStatusBar systemStatusBar] removeStatusItem:self.statusItem];
    self.statusItem = nil;
}

/// Glifo de rede desenhado em código: um nó ligado a dois. Imagem template, então
/// o sistema inverte sozinho em barra clara/escura — nada de PNG por densidade.
/// SF Symbols resolveria em uma linha, mas só existe do macOS 11 em diante.
- (NSImage *)statusImage {
    NSSize size = NSMakeSize(18.0, 18.0);
    NSImage *image = [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect rect) {
        NSPoint top   = NSMakePoint(9.0, 13.5);
        NSPoint left  = NSMakePoint(4.0, 4.5);
        NSPoint right = NSMakePoint(14.0, 4.5);
        CGFloat radius = 2.4;

        [[NSColor blackColor] setStroke];
        [[NSColor blackColor] setFill];

        NSBezierPath *links = [NSBezierPath bezierPath];
        links.lineWidth = 1.4;
        links.lineCapStyle = NSLineCapStyleRound;
        [links moveToPoint:top];   [links lineToPoint:left];
        [links moveToPoint:top];   [links lineToPoint:right];
        [links moveToPoint:left];  [links lineToPoint:right];
        [links stroke];

        for (NSValue *value in @[ [NSValue valueWithPoint:top],
                                  [NSValue valueWithPoint:left],
                                  [NSValue valueWithPoint:right] ]) {
            NSPoint p = value.pointValue;
            NSRect dot = NSMakeRect(p.x - radius, p.y - radius, radius * 2, radius * 2);
            [[NSBezierPath bezierPathWithOvalInRect:dot] fill];
        }
        return YES;
    }];
    image.template = YES;
    return image;
}

#pragma mark - NSMenuDelegate

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];

    NSArray<MMShare *> *shares = [MMStore shared].shares;
    MMCoordinator *coordinator = [MMCoordinator shared];

    if (shares.count == 0) {
        NSMenuItem *empty = [[NSMenuItem alloc]
            initWithTitle:NSLocalizedString(@"menu.empty", @"Nenhum compartilhamento")
                   action:NULL keyEquivalent:@""];
        empty.enabled = NO;
        [menu addItem:empty];
    }

    BOOL anyUnmounted = NO;
    for (NSUInteger i = 0; i < shares.count; i++) {
        MMShare *share = shares[i];
        MMMountState state = [coordinator stateForShare:share];
        if (state == MMMountStateUnmounted) anyUnmounted = YES;

        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:share.displayName
                                                      action:@selector(toggleShare:)
                                               keyEquivalent:@""];
        item.target = self;
        item.tag = (NSInteger)i;
        item.state = (state == MMMountStateMounted) ? NSControlStateValueOn : NSControlStateValueOff;
        item.enabled = (state == MMMountStateMounted || state == MMMountStateUnmounted);

        switch (state) {
            case MMMountStateMounting:
                item.title = [NSString stringWithFormat:@"%@ — %@", share.displayName,
                              NSLocalizedString(@"state.mounting", @"Montando…")];
                break;
            case MMMountStateUnmounting:
                item.title = [NSString stringWithFormat:@"%@ — %@", share.displayName,
                              NSLocalizedString(@"state.unmounting", @"Desmontando…")];
                break;
            default:
                break;
        }

        // Alt no item revela o volume no Finder em vez de desmontar.
        if (state == MMMountStateMounted) {
            NSMenuItem *reveal = [[NSMenuItem alloc]
                initWithTitle:[NSString stringWithFormat:
                               NSLocalizedString(@"menu.revealFmt", @"Abrir “%@” no Finder"),
                               share.displayName]
                       action:@selector(revealShare:) keyEquivalent:@""];
            reveal.target = self;
            reveal.tag = (NSInteger)i;
            reveal.alternate = YES;
            reveal.keyEquivalentModifierMask = NSEventModifierFlagOption;
            [menu addItem:item];
            [menu addItem:reveal];
            continue;
        }

        [menu addItem:item];
    }

    [menu addItem:[NSMenuItem separatorItem]];

    if (anyUnmounted) {
        NSMenuItem *mountAll = [[NSMenuItem alloc]
            initWithTitle:NSLocalizedString(@"bar.mountAll", @"Montar todos")
                   action:@selector(mountAll:) keyEquivalent:@""];
        mountAll.target = self;
        [menu addItem:mountAll];
    }

    NSMenuItem *add = [[NSMenuItem alloc]
        initWithTitle:NSLocalizedString(@"menu.add", @"Adicionar compartilhamento…")
               action:@selector(addShare:) keyEquivalent:@""];
    add.target = self;
    [menu addItem:add];

    NSMenuItem *open = [[NSMenuItem alloc]
        initWithTitle:NSLocalizedString(@"menu.open", @"Abrir MacMount")
               action:@selector(openWindow:) keyEquivalent:@""];
    open.target = self;
    [menu addItem:open];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quit = [[NSMenuItem alloc]
        initWithTitle:NSLocalizedString(@"menu.quit", @"Sair do MacMount")
               action:@selector(terminate:) keyEquivalent:@"q"];
    quit.target = NSApp;
    [menu addItem:quit];
}

#pragma mark - Ações

- (nullable MMShare *)shareForItem:(NSMenuItem *)item {
    NSArray<MMShare *> *shares = [MMStore shared].shares;
    if (item.tag < 0 || item.tag >= (NSInteger)shares.count) return nil;
    return shares[item.tag];
}

- (void)toggleShare:(NSMenuItem *)sender {
    MMShare *share = [self shareForItem:sender];
    if (share != nil) [[MMCoordinator shared] toggleShare:share];
}

- (void)revealShare:(NSMenuItem *)sender {
    MMShare *share = [self shareForItem:sender];
    if (share != nil) [[MMCoordinator shared] revealShareInFinder:share];
}

- (void)mountAll:(id)sender {
    [[MMCoordinator shared] mountAll];
}

- (void)addShare:(id)sender {
    [[MMMainWindow shared] showAndActivate];
    [[MMMainWindow shared] addShare:sender];
}

- (void)openWindow:(id)sender {
    [[MMMainWindow shared] showAndActivate];
}

@end
