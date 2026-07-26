//
//  MMStatusMenu.m
//

#import "MMStatusMenu.h"

#import "MMCoordinator.h"
#import "MMMainWindow.h"
#import "MMPrefs.h"
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

/// Ícone de HD interno do Mac para a barra de menus.
/// Desenhado em código como template (monocromático com alfa), o que permite ao
/// sistema inverter automaticamente para barra clara ou escura.
/// O estilo imita o ícone clássico de disco interno do Finder: corpo mais quadrado,
/// janela circular das bandejas de disco e detalhes do conector traseiro.
- (NSImage *)statusImage {
    NSSize size = NSMakeSize(18.0, 18.0);
    NSImage *image = [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [[NSColor blackColor] setStroke];
        [[NSColor blackColor] setFill];

        // Corpo principal — mais quadrado que o externo, tipo HD 3.5" interno.
        NSRect body = NSMakeRect(1.5, 3.5, 15.0, 11.0);
        NSBezierPath *shell = [NSBezierPath bezierPathWithRoundedRect:body
                                                              xRadius:1.8
                                                              yRadius:1.8];
        shell.lineWidth = 1.3;
        [shell stroke];

        // Janela circular das bandejas (o que distingue "interno" de "externo"
        // no vocabulário visual do Finder).
        NSRect platter = NSMakeRect(3.2, 5.5, 5.8, 5.8);
        NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:platter];
        circle.lineWidth = 1.2;
        [circle stroke];

        // Anel interno da bandeja (profundidade).
        NSRect innerRing = NSMakeRect(5.0, 7.3, 2.2, 2.2);
        [[NSBezierPath bezierPathWithOvalInRect:innerRing] fill];

        // Linhas do PCB/conector — direita do corpo.
        CGFloat lx = NSMaxX(body) - 4.0;
        for (int i = 0; i < 3; i++) {
            CGFloat ly = NSMinY(body) + 2.5 + i * 2.2;
            NSBezierPath *line = [NSBezierPath bezierPath];
            line.lineWidth = 0.9;
            [line moveToPoint:NSMakePoint(lx, ly)];
            [line lineToPoint:NSMakePoint(NSMaxX(body) - 1.8, ly)];
            [line stroke];
        }

        // Entalhe do conector traseiro (borda superior).
        NSRect notch = NSMakeRect(6.0, NSMaxY(body) - 0.1, 6.0, 1.5);
        NSBezierPath *notchPath = [NSBezierPath bezierPathWithRoundedRect:notch
                                                                  xRadius:0.8
                                                                  yRadius:0.8];
        [notchPath fill];

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

    for (NSUInteger i = 0; i < shares.count; i++) {
        MMShare *share = shares[i];
        MMMountState state = [coordinator stateForShare:share];
        BOOL settled = (state == MMMountStateMounted || state == MMMountStateUnmounted);

        // Parado, o nome fala por si; em trânsito, ganha o estado como sufixo.
        NSString *title = settled
            ? share.displayName
            : [NSString stringWithFormat:@"%@ — %@", share.displayName, MMMountStateTitle(state)];

        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                      action:@selector(toggleShare:)
                                               keyEquivalent:@""];
        item.target = self;
        item.tag = (NSInteger)i;
        item.state = (state == MMMountStateMounted) ? NSControlStateValueOn : NSControlStateValueOff;
        item.enabled = settled;

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

    if ([coordinator hasSharesInState:MMMountStateUnmounted]) {
        NSMenuItem *mountAll = [[NSMenuItem alloc]
            initWithTitle:NSLocalizedString(@"bar.mountAll", @"Montar todos")
                   action:@selector(mountAll:) keyEquivalent:@""];
        mountAll.target = self;
        [menu addItem:mountAll];
    }

    if ([coordinator hasSharesInState:MMMountStateMounted]) {
        NSMenuItem *unmountAll = [[NSMenuItem alloc]
            initWithTitle:NSLocalizedString(@"bar.unmountAll", @"Desmontar todos")
                   action:@selector(unmountAll:) keyEquivalent:@""];
        unmountAll.target = self;
        [menu addItem:unmountAll];
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

    // Único lugar onde o interruptor cabe: desligado o ícone do Dock, o menu
    // principal do app some junto, e este menu vira a casa das preferências.
    NSMenuItem *dockIcon = [[NSMenuItem alloc]
        initWithTitle:NSLocalizedString(@"menu.showDockIcon", @"Mostrar ícone no Dock")
               action:@selector(toggleDockIcon:) keyEquivalent:@""];
    dockIcon.target = self;
    dockIcon.state = MMPrefs.showDockIcon ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:dockIcon];

    NSMenuItem *darkMode = [[NSMenuItem alloc]
        initWithTitle:NSLocalizedString(@"menu.darkMode", @"Interface escura")
               action:@selector(toggleDarkMode:) keyEquivalent:@""];
    darkMode.target = self;
    darkMode.state = MMPrefs.forceDarkMode ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:darkMode];

    NSMenuItem *notify = [[NSMenuItem alloc]
        initWithTitle:NSLocalizedString(@"menu.notifyOnLogin", @"Avisar ao montar no login")
               action:@selector(toggleLoginNotification:) keyEquivalent:@""];
    notify.target = self;
    notify.state = MMPrefs.notifyOnLoginMount ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:notify];

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

- (void)unmountAll:(id)sender {
    [[MMCoordinator shared] unmountAll];
}

- (void)toggleDockIcon:(id)sender {
    MMPrefs.showDockIcon = !MMPrefs.showDockIcon;
}

- (void)toggleDarkMode:(id)sender {
    MMPrefs.forceDarkMode = !MMPrefs.forceDarkMode;
}

- (void)toggleLoginNotification:(id)sender {
    MMPrefs.notifyOnLoginMount = !MMPrefs.notifyOnLoginMount;
}

- (void)addShare:(id)sender {
    [[MMMainWindow shared] showAndActivate];
    [[MMMainWindow shared] addShare:sender];
}

- (void)openWindow:(id)sender {
    [[MMMainWindow shared] showAndActivate];
}

@end
