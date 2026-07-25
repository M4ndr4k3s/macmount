//
//  MMAppDelegate.m
//

#import "MMAppDelegate.h"

#import "MMCoordinator.h"
#import "MMEditSheet.h"
#import "MMLoginItem.h"
#import "MMMainWindow.h"
#import "MMPrefs.h"
#import "MMReconnector.h"
#import "MMShare.h"
#import "MMStatusMenu.h"
#import "MMStore.h"

/// Teto para a montagem automática do login: sem isso, um servidor sumido
/// deixaria o processo vivo para sempre esperando um soft mount desistir.
static NSTimeInterval const MMLoginModeTimeout = 120.0;

@interface MMAppDelegate ()
@property (nonatomic, strong) MMStatusMenu *statusMenu;
@property (nonatomic, strong) MMReconnector *reconnector;
@property (nonatomic, strong) NSTimer *loginWatchdog;
@property (nonatomic, strong) NSDate *loginStartedAt;
@property (nonatomic, assign) NSUInteger loginMountTarget;
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

    self.reconnector = [[MMReconnector alloc] init];
    [self.reconnector start];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applyDockIconPreference)
                                                 name:MMPrefsDidChangeNotification
                                               object:nil];
    [self applyDockIconPreference];

    [[MMMainWindow shared] showAndActivate];
}

/// Com o ícone escondido o app vira "accessory": some do Dock e do alternador
/// de apps, ficando só na barra de menus. O menu principal também deixa de ser
/// exibido, mas continua montado de propósito — é ele que faz Cmd+C e Cmd+V
/// funcionarem nos campos de texto da folha de edição.
- (void)applyDockIconPreference {
    NSApplicationActivationPolicy wanted = MMPrefs.showDockIcon
        ? NSApplicationActivationPolicyRegular
        : NSApplicationActivationPolicyAccessory;

    if (NSApp.activationPolicy == wanted) return;
    [NSApp setActivationPolicy:wanted];

    // Voltar para "regular" sem reativar deixa o app sem foco e sem menu.
    if (wanted == NSApplicationActivationPolicyRegular) {
        [NSApp activateIgnoringOtherApps:YES];
    }
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
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.loginWatchdog invalidate];
    self.loginWatchdog = nil;
    [self.reconnector stop];
    [self.statusMenu remove];
}

#pragma mark - Montagem no login

- (void)startLoginMount {
    MMCoordinator *coordinator = [MMCoordinator shared];
    coordinator.silent = YES;

    NSUInteger flagged = 0;
    for (MMShare *share in [MMStore shared].shares) {
        if (share.mountAtLogin) flagged++;
    }
    self.loginMountTarget = flagged;

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
    if (!done && !timedOut) return;

    [timer invalidate];
    self.loginWatchdog = nil;
    [self notifyLoginMountResult];

    // A notificação é entregue de forma assíncrona pelo sistema; encerrar no
    // mesmo ciclo de run loop a engoliria antes de aparecer.
    [self performSelector:@selector(terminateNow) withObject:nil afterDelay:1.5];
}

- (void)terminateNow {
    [NSApp terminate:nil];
}

/// Notificação nativa do 10.13. O UNUserNotificationCenter só existe do 10.14
/// em diante, então usar a API nova exigiria caminho duplo ou abandonar o
/// High Sierra — que é justamente o alvo deste app. O aviso de obsolescência
/// é silenciado de propósito.
- (void)notifyLoginMountResult {
    if (!MMPrefs.notifyOnLoginMount || self.loginMountTarget == 0) return;

    NSUInteger mounted = 0;
    for (MMShare *share in [MMStore shared].shares) {
        if (!share.mountAtLogin) continue;
        if ([[MMCoordinator shared] stateForShare:share] == MMMountStateMounted) mounted++;
    }

    NSString *body;
    if (mounted == self.loginMountTarget) {
        body = (mounted == 1)
            ? NSLocalizedString(@"notify.oneMounted", @"1 compartilhamento montado.")
            : [NSString stringWithFormat:
               NSLocalizedString(@"notify.allMountedFmt", @"%lu compartilhamentos montados."),
               (unsigned long)mounted];
    } else {
        body = [NSString stringWithFormat:
                NSLocalizedString(@"notify.partialFmt", @"%lu de %lu compartilhamentos montados."),
                (unsigned long)mounted, (unsigned long)self.loginMountTarget];
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSUserNotification *note = [[NSUserNotification alloc] init];
    note.title = NSLocalizedString(@"app.name", @"MacMount");
    note.informativeText = body;
    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:note];
#pragma clang diagnostic pop
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

    // A folha de edição é o formulário mais denso do app e a sua altura vem do
    // conteúdo, não de um número fixo — acrescentar uma linha e cortar os
    // botões seria fácil, e ninguém abre essa tela antes de publicar.
    NSWindow *sheet = [MMEditSheet buildSheetForSmokeTest];
    if (sheet == nil) {
        fprintf(stderr, "smoke: folha de edição não foi criada\n");
        ok = NO;
    } else {
        NSSize size = sheet.frame.size;
        NSSize fitting = [sheet.contentView fittingSize];
        if (size.height + 1.0 < fitting.height || size.width + 1.0 < fitting.width) {
            fprintf(stderr, "smoke: folha menor que o conteúdo (%.0fx%.0f para caber %.0fx%.0f)\n",
                    size.width, size.height, fitting.width, fitting.height);
            ok = NO;
        } else {
            fprintf(stdout, "smoke: folha de edição %.0fx%.0f comporta o formulário\n",
                    size.width, size.height);
        }
    }

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
