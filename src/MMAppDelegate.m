//
//  MMAppDelegate.m
//

#import "MMAppDelegate.h"

#import "MMCoordinator.h"
#import "MMEditSheet.h"
#import "MMLoginItem.h"
#import "MMMainWindow.h"
#import "MMShare.h"
#import "MMStatusMenu.h"
#import "MMStore.h"

/// Teto para a montagem automática do login: sem isso, um servidor sumido
/// deixaria o processo vivo para sempre esperando um soft mount desistir.
static NSTimeInterval const MMLoginModeTimeout = 120.0;

@interface MMAppDelegate ()
@property (nonatomic, strong) MMStatusMenu *statusMenu;
@property (nonatomic, strong) NSTimer *loginWatchdog;
@property (nonatomic, strong) NSDate *loginStartedAt;
@end

@implementation MMAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [[MMCoordinator shared] startObservingVolumes];
    [MMLoginItem refreshIfInstalled];

    if (self.mountAtLoginMode) {
        [self startLoginMount];
        return;
    }

    [self buildMainMenu];

    self.statusMenu = [[MMStatusMenu alloc] init];
    [self.statusMenu install];

    [[MMMainWindow shared] showAndActivate];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    [[MMMainWindow shared] showAndActivate];
    return YES;
}

/// A janela fechada não encerra o app: o ícone da barra continua servindo.
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.loginWatchdog invalidate];
    self.loginWatchdog = nil;
    [self.statusMenu remove];
}

#pragma mark - Montagem no login

- (void)startLoginMount {
    MMCoordinator *coordinator = [MMCoordinator shared];
    coordinator.silent = YES;
    [coordinator mountFlaggedForLogin];

    self.loginStartedAt = [NSDate date];
    self.loginWatchdog = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                          target:self
                                                        selector:@selector(checkLoginMountFinished:)
                                                        userInfo:nil
                                                         repeats:YES];
}

- (void)checkLoginMountFinished:(NSTimer *)timer {
    BOOL done = ![[MMCoordinator shared] hasPendingOperations];
    BOOL timedOut = [[NSDate date] timeIntervalSinceDate:self.loginStartedAt] > MMLoginModeTimeout;

    if (timedOut && !done) {
        NSLog(@"[MacMount] montagem no login excedeu %.0fs; encerrando.", MMLoginModeTimeout);
    }
    if (done || timedOut) {
        [timer invalidate];
        self.loginWatchdog = nil;
        [NSApp terminate:nil];
    }
}

#pragma mark - Menu principal

- (void)buildMainMenu {
    NSString *appName = NSLocalizedString(@"app.name", @"MacMount");

    NSMenu *mainMenu = [[NSMenu alloc] init];

    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    NSMenu *appMenu = [[NSMenu alloc] init];
    [appMenu addItemWithTitle:[NSString stringWithFormat:
                               NSLocalizedString(@"menu.aboutFmt", @"Sobre o %@"), appName]
                       action:@selector(orderFrontStandardAboutPanel:)
                keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:NSLocalizedString(@"menu.add", @"Adicionar compartilhamento…")
                       action:@selector(addShare:)
                keyEquivalent:@"n"];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:[NSString stringWithFormat:
                               NSLocalizedString(@"menu.hideFmt", @"Ocultar %@"), appName]
                       action:@selector(hide:)
                keyEquivalent:@"h"];
    [appMenu addItemWithTitle:[NSString stringWithFormat:
                               NSLocalizedString(@"menu.quitFmt", @"Sair do %@"), appName]
                       action:@selector(terminate:)
                keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    [mainMenu addItem:appItem];

    NSMenuItem *editItem = [[NSMenuItem alloc] init];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:NSLocalizedString(@"menu.edit", @"Editar")];
    [editMenu addItemWithTitle:NSLocalizedString(@"menu.cut", @"Recortar")
                        action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:NSLocalizedString(@"menu.copy", @"Copiar")
                        action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:NSLocalizedString(@"menu.paste", @"Colar")
                        action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:NSLocalizedString(@"menu.selectAll", @"Selecionar tudo")
                        action:@selector(selectAll:) keyEquivalent:@"a"];
    editItem.submenu = editMenu;
    [mainMenu addItem:editItem];

    NSMenuItem *windowItem = [[NSMenuItem alloc] init];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:NSLocalizedString(@"menu.window", @"Janela")];
    [windowMenu addItemWithTitle:NSLocalizedString(@"menu.minimize", @"Minimizar")
                          action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:NSLocalizedString(@"menu.close", @"Fechar")
                          action:@selector(performClose:) keyEquivalent:@"w"];
    windowItem.submenu = windowMenu;
    [mainMenu addItem:windowItem];

    NSApp.mainMenu = mainMenu;
    NSApp.windowsMenu = windowMenu;
}

/// Alvo do Cmd+N do menu principal — segue a cadeia de resposta até aqui.
- (void)addShare:(id)sender {
    [[MMMainWindow shared] showAndActivate];
    [[MMMainWindow shared] addShare:sender];
}

#pragma mark - Smoke test

- (BOOL)runSmokeTest {
    BOOL ok = YES;

    [self buildMainMenu];
    if (NSApp.mainMenu.numberOfItems < 3) {
        fprintf(stderr, "smoke: menu principal incompleto\n");
        ok = NO;
    }

    MMStatusMenu *status = [[MMStatusMenu alloc] init];
    [status install];
    [status remove];

    MMMainWindow *window = [MMMainWindow shared];
    if (window.window == nil) {
        fprintf(stderr, "smoke: janela principal não foi criada\n");
        ok = NO;
    }
    // Força o layout sem exibir: é aqui que constraint quebrada aparece.
    [window.window.contentView layoutSubtreeIfNeeded];

    // A folha de edição é construída fora da tela, com uma entrada de exemplo.
    MMShare *sample = [MMShare shareWithUserInput:@"\\\\SERVIDOR\\Publico"];
    if (![sample.host isEqualToString:@"SERVIDOR"]) {
        fprintf(stderr, "smoke: parser de UNC devolveu host inesperado: %s\n",
                sample.host.UTF8String);
        ok = NO;
    }

    if ([MMStore shared] == nil) {
        fprintf(stderr, "smoke: store não inicializou\n");
        ok = NO;
    }

    if (ok) fprintf(stdout, "smoke: interface construída sem erros\n");
    return ok;
}

@end
