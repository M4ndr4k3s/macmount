//
//  MMAppDelegate.m
//

#import "MMAppDelegate.h"

#import "MMCoordinator.h"
#import "MMLoginItem.h"
#import "MMLoginMount.h"
#import "MMMainMenu.h"
#import "MMMainWindow.h"
#import "MMPrefs.h"
#import "MMReconnector.h"
#import "MMStatusMenu.h"
#import "MMStore.h"

@interface MMAppDelegate ()
@property (nonatomic, strong) MMStatusMenu *statusMenu;
@property (nonatomic, strong) MMReconnector *reconnector;
@property (nonatomic, strong) MMLoginMount *loginMount;
@end

@implementation MMAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [[MMCoordinator shared] startObservingVolumes];
    [MMLoginItem refreshIfInstalled];

    if (self.mountAtLoginMode) {
        self.loginMount = [[MMLoginMount alloc] init];
        [self.loginMount startWithCompletion:^{ [NSApp terminate:nil]; }];
        return;
    }

    [MMMainMenu install];

    self.statusMenu = [[MMStatusMenu alloc] init];
    [self.statusMenu install];

    self.reconnector = [[MMReconnector alloc] init];
    [self.reconnector start];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applyDockIconPreference)
                                                 name:MMPrefsDidChangeNotification
                                               object:nil];
    [self applyDockIconPreference];

    // Sem isto a caixa "montar ao iniciar a sessão" grava a marca e não produz
    // efeito nenhum: é o LaunchAgent que faz o login abrir o app.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(syncLoginItem)
                                                 name:MMStoreDidChangeNotification
                                               object:nil];
    [self syncLoginItem];

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

- (void)syncLoginItem {
    [MMLoginItem syncWithShares:[MMStore shared].shares];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    // No modo login o processo existe só para montar e encerrar. Um evento de
    // reabertura chegando aqui — o Dock, o Finder ou o próprio launchd pedindo
    // para "abrir o app" — materializaria a janela no meio do login. É o único
    // caminho que ainda podia trazê-la de volta, e ele fica fechado.
    if (self.mountAtLoginMode) return NO;

    [[MMMainWindow shared] showAndActivate];
    return YES;
}

/// A janela fechada não encerra o app: o ícone da barra continua servindo.
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.reconnector stop];
    [self.statusMenu remove];
}

/// Alvo do Cmd+N do menu principal — segue a cadeia de resposta até aqui.
- (void)addShare:(id)sender {
    [[MMMainWindow shared] showAndActivate];
    [[MMMainWindow shared] addShare:sender];
}

@end
