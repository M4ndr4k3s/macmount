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

/// Silhueta de disco externo, para conversar com o ícone do Dock. Desenhada em
/// código e marcada como template: a barra de menus exige monocromático com
/// alfa, porque é o sistema que inverte a cor entre barra clara e escura —
/// reduzir o ícone colorido do app aqui daria uma mancha que some no escuro.
/// SF Symbols resolveria em uma linha, mas só existe do macOS 11 em diante.
- (NSImage *)statusImage {
    NSSize size = NSMakeSize(18.0, 18.0);
    NSImage *image = [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [[NSColor blackColor] setStroke];
        [[NSColor blackColor] setFill];

        // Corpo do disco. Meio pixel de deslocamento para o traço cair sobre a
        // grade e não sair borrado em tela sem retina.
        NSRect body = NSMakeRect(2.5, 4.5, 13.0, 9.0);
        NSBezierPath *shell = [NSBezierPath bezierPathWithRoundedRect:body
                                                              xRadius:2.2
                                                              yRadius:2.2];
        shell.lineWidth = 1.4;
        [shell stroke];

        // Emenda entre tampa e carcaça, o que faz a forma ler como "disco" e
        // não como um retângulo qualquer.
        NSBezierPath *seam = [NSBezierPath bezierPath];
        seam.lineWidth = 1.2;
        [seam moveToPoint:NSMakePoint(NSMinX(body), 10.0)];
        [seam lineToPoint:NSMakePoint(NSMaxX(body), 10.0)];
        [seam stroke];

        // Luz de atividade.
        NSRect led = NSMakeRect(4.6, 6.4, 2.0, 2.0);
        [[NSBezierPath bezierPathWithOvalInRect:led] fill];

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

    if ([coordinator hasMountedShares]) {
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
