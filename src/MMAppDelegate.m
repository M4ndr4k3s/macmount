//
//  MMAppDelegate.m
//

#import "MMAppDelegate.h"

#include <unistd.h>

#import "MMCoordinator.h"
#import "MMLoginItem.h"
#import "MMLoginMount.h"
#import "MMMainMenu.h"
#import "MMMainWindow.h"
#import "MMPrefs.h"
#import "MMReconnector.h"
#import "MMStatusMenu.h"
#import "MMStore.h"

/// Aplica ou remove o tema escuro forçado no app inteiro.
/// Requer 10.14; no High Sierra a guarda impede a execução em tempo de compilação.
static void MMApplyAppearance(void) {
    if (@available(macOS 10.14, *)) {
        NSAppearanceName name = MMPrefs.forceDarkMode
            ? NSAppearanceNameDarkAqua
            : NSAppearanceNameAqua;
        NSApp.appearance = [NSAppearance appearanceNamed:name];
    }
}

@interface MMAppDelegate ()
@property (nonatomic, strong) MMStatusMenu *statusMenu;
@property (nonatomic, strong) MMReconnector *reconnector;
@property (nonatomic, strong) MMLoginMount *loginMount;
/// Ligado durante toda a abertura junto com a sessão, inclusive antes de a
/// montagem começar. É o que impede o app de roubar o foco ou abrir a janela
/// num momento em que o combinado é não aparecer.
@property (nonatomic, assign) BOOL startingWithSession;
@end

@implementation MMAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    if ([self anotherInstanceIsRunning]) {
        NSLog(@"[MacMount] já há uma cópia em execução; encerrando esta.");
        [NSApp terminate:nil];
        return;
    }

    // A montagem automática vale para os dois jeitos de o app nascer junto com a
    // sessão: o nosso LaunchAgent, que passa --mount-at-login, e os Itens de
    // Início do sistema, que não passam nada — daí a segunda pergunta.
    self.startingWithSession = self.mountAtLoginMode || [self wasLaunchedAutomatically:notification];

    MMApplyAppearance();

    [[MMCoordinator shared] startObservingVolumes];
    [MMLoginItem refreshIfInstalled];

    [MMMainMenu install];

    self.statusMenu = [[MMStatusMenu alloc] init];
    [self.statusMenu install];

    self.reconnector = [[MMReconnector alloc] init];
    [self.reconnector start];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applyAppearancePreference)
                                                 name:MMPrefsDidChangeNotification
                                               object:nil];
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

    if (self.startingWithSession) {
        [self startSessionMount];
        return;   // nenhuma janela: o app fica na barra de menus
    }

    [[MMMainWindow shared] showAndActivate];
}

/// O launchd inicia o executável direto, por dentro do pacote, sem passar pelo
/// LaunchServices — então ele não deduplica, e uma cópia pelo LaunchAgent mais
/// outra pelos Itens de Início do sistema convivem no mesmo login. Duas cópias
/// montando o mesmo compartilhamento ao mesmo tempo é receita de montagem
/// travada, e a segunda ainda abre a janela que não deveria existir.
- (BOOL)anotherInstanceIsRunning {
    NSString *identifier = [[NSBundle mainBundle] bundleIdentifier];
    if (identifier.length == 0) return NO;

    pid_t mine = getpid();
    for (NSRunningApplication *app in
         [NSRunningApplication runningApplicationsWithBundleIdentifier:identifier]) {
        if (app.processIdentifier != mine && !app.terminated) return YES;
    }
    return NO;
}

/// Aberto pelo sistema (Itens de Início, retomada de sessão) em vez de por um
/// duplo clique. Existe desde o 10.8; ausente, tratamos como abertura normal.
- (BOOL)wasLaunchedAutomatically:(NSNotification *)notification {
    NSNumber *byUser = notification.userInfo[NSApplicationLaunchIsDefaultLaunchKey];
    return byUser != nil && !byUser.boolValue;
}

/// Monta o que está marcado, calado, e devolve o app ao modo normal no fim —
/// sem isso o resto da sessão ficaria sem alerta nenhum de erro.
- (void)startSessionMount {
    self.loginMount = [[MMLoginMount alloc] init];
    [self.loginMount startWithCompletion:^{
        [MMCoordinator shared].silent = NO;
        self.loginMount = nil;
        self.startingWithSession = NO;
    }];
}

/// Com o ícone escondido o app vira "accessory": some do Dock e do alternador
/// de apps, ficando só na barra de menus. O menu principal também deixa de ser
/// exibido, mas continua montado de propósito — é ele que faz Cmd+C e Cmd+V
/// funcionarem nos campos de texto da folha de edição.
- (void)applyAppearancePreference {
    MMApplyAppearance();
}

- (void)applyDockIconPreference {
    NSApplicationActivationPolicy wanted = MMPrefs.showDockIcon
        ? NSApplicationActivationPolicyRegular
        : NSApplicationActivationPolicyAccessory;

    if (NSApp.activationPolicy == wanted) return;
    [NSApp setActivationPolicy:wanted];

    // Voltar para "regular" sem reativar deixa o app sem foco e sem menu. Mas no
    // início da sessão isso roubaria o foco de quem está fazendo outra coisa, e
    // o combinado ali é justamente não aparecer.
    if (wanted == NSApplicationActivationPolicyRegular && !self.startingWithSession) {
        [NSApp activateIgnoringOtherApps:YES];
    }
}

- (void)syncLoginItem {
    [MMLoginItem syncWithShares:[MMStore shared].shares];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    // Durante a montagem do início da sessão, um pedido de "abrir o app" — do
    // Dock, do Finder ou do próprio launchd — materializaria a janela no meio do
    // login. Depois disso, reabrir volta a significar o que significa sempre.
    if (self.startingWithSession) return NO;

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
