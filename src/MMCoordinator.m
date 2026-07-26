//
//  MMCoordinator.m
//

#import "MMCoordinator.h"

#import <AppKit/AppKit.h>

#include <errno.h>

#import "MMAlerts.h"
#import "MMKeychain.h"
#import "MMMounter.h"
#import "MMStore.h"

NSString *const MMCoordinatorDidChangeNotification = @"MMCoordinatorDidChangeNotification";

NSString *MMMountStateTitle(MMMountState state) {
    switch (state) {
        case MMMountStateMounted:     return NSLocalizedString(@"state.mounted", @"Montado");
        case MMMountStateMounting:    return NSLocalizedString(@"state.mounting", @"Montando…");
        case MMMountStateUnmounting:  return NSLocalizedString(@"state.unmounting", @"Desmontando…");
        case MMMountStateUnmounted:
        default:                      return NSLocalizedString(@"state.unmounted", @"Desmontado");
    }
}

NSString *MMMountStateActionTitle(MMMountState state) {
    switch (state) {
        case MMMountStateMounted:     return NSLocalizedString(@"action.unmount", @"Desmontar");
        case MMMountStateUnmounted:   return NSLocalizedString(@"action.mount", @"Montar");
        default:                      return MMMountStateTitle(state);
    }
}

/// Prazo de uma operação em trânsito. `NetFSMountURLSync` é síncrono e não
/// aceita prazo nenhum: contra um servidor que sumiu, um nome que ainda não
/// resolve — o caso típico logo depois de um reinício, com o Wi-Fi recém
/// associado — ou um diálogo de credencial que nasceu atrás das outras janelas,
/// ele fica muito tempo sem responder. Passado este prazo o app para de esperar
/// e volta a confiar no que o sistema diz, liberando nova tentativa.
///
/// Generoso de propósito: montagem legítima de servidor lento leva dezenas de
/// segundos, e desistir cedo demais transformaria lentidão em erro.
static NSTimeInterval const MMOperationTimeout = 90.0;

/// De quanto em quanto tempo as operações em trânsito são reavaliadas. Só roda
/// enquanto existe alguma.
static NSTimeInterval const MMOperationSweepInterval = 1.0;

/// Uma montagem ou desmontagem em andamento.
@interface MMPendingOperation : NSObject
@property (nonatomic, assign) MMMountState state;
@property (nonatomic, strong) NSDate *startedAt;
/// Cada tentativa recebe um número. Uma tentativa que travou e respondeu tarde
/// não pode mexer no estado de outra que começou depois dela.
@property (nonatomic, assign) NSUInteger generation;
@end

@implementation MMPendingOperation
@end

@interface MMCoordinator ()
/// Só operações em trânsito; "montado" é sempre perguntado ao sistema, nunca
/// guardado — assim o app não mente quando alguém desmonta pelo Finder.
@property (nonatomic, strong) NSMutableDictionary<NSString *, MMPendingOperation *> *pending;
@property (nonatomic, strong, nullable) NSTimer *sweepTimer;
@property (nonatomic, assign) NSUInteger lastGeneration;
@end

// Os blocos de conclusão abaixo capturam self sem __weak de propósito: o
// coordenador é o singleton de +shared, criado com dispatch_once e vivo até o
// processo terminar, então a dança weak/strong só acrescentaria ruído sugerindo
// um ciclo de vida que não existe. Ciclo de retenção também não há — o
// MMMounter não guarda o bloco, apenas o chama uma vez e o descarta.

@implementation MMCoordinator

+ (MMCoordinator *)shared {
    static MMCoordinator *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[MMCoordinator alloc] init]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _pending = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)startObservingVolumes {
    NSNotificationCenter *center = [[NSWorkspace sharedWorkspace] notificationCenter];
    [center addObserver:self selector:@selector(volumesChanged:)
                   name:NSWorkspaceDidMountNotification object:nil];
    [center addObserver:self selector:@selector(volumesChanged:)
                   name:NSWorkspaceDidUnmountNotification object:nil];
    [center addObserver:self selector:@selector(volumesChanged:)
                   name:NSWorkspaceDidRenameVolumeNotification object:nil];
}

- (void)dealloc {
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
}

- (void)volumesChanged:(NSNotification *)note {
    [self notifyChanged];
}

- (void)notifyChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:MMCoordinatorDidChangeNotification
                                                        object:self];
}

#pragma mark - Estado

/// O sistema tem a palavra final. A operação em trânsito só é levada em conta
/// enquanto ainda faz sentido — ver +operationSettledMounting:… no MMMounter.
- (MMMountState)stateForShare:(MMShare *)share {
    BOOL mounted = ([MMMounter mountPointForShare:share] != nil);

    MMPendingOperation *op = self.pending[share.identifier];
    if (op != nil && ![self operation:op settledWithMounted:mounted]) return op.state;

    return mounted ? MMMountStateMounted : MMMountStateUnmounted;
}

- (BOOL)operation:(MMPendingOperation *)op settledWithMounted:(BOOL)mounted {
    return [MMMounter operationSettledMounting:(op.state == MMMountStateMounting)
                                       mounted:mounted
                                       elapsed:-[op.startedAt timeIntervalSinceNow]
                                       timeout:MMOperationTimeout];
}

- (nullable NSString *)mountPointForShare:(MMShare *)share {
    return [MMMounter mountPointForShare:share];
}

/// Abre uma operação e devolve o número dela, que o bloco de conclusão precisa
/// apresentar depois para provar que ainda é a tentativa vigente.
- (NSUInteger)beginOperation:(MMMountState)state forShare:(MMShare *)share {
    MMPendingOperation *op = [[MMPendingOperation alloc] init];
    op.state = state;
    op.startedAt = [NSDate date];
    op.generation = ++self.lastGeneration;

    self.pending[share.identifier] = op;
    [self startSweeping];
    [self notifyChanged];
    return op.generation;
}

- (BOOL)isCurrentOperation:(NSUInteger)generation forShare:(MMShare *)share {
    MMPendingOperation *op = self.pending[share.identifier];
    return op != nil && op.generation == generation;
}

- (void)endOperation:(NSUInteger)generation forShare:(MMShare *)share {
    if (![self isCurrentOperation:generation forShare:share]) return;
    [self.pending removeObjectForKey:share.identifier];
    [self notifyChanged];
}

- (BOOL)hasPendingOperations {
    return self.pending.count > 0;
}

#pragma mark - Varredura das operações em trânsito

/// Sem isto, uma operação que vence o prazo — ou que o sistema já resolveu por
/// outro caminho — só apareceria na tela no próximo evento de volume, que pode
/// nunca vir. O relógio existe só enquanto há o que vigiar.
- (void)startSweeping {
    if (self.sweepTimer != nil) return;
    self.sweepTimer = [NSTimer scheduledTimerWithTimeInterval:MMOperationSweepInterval
                                                       target:self
                                                     selector:@selector(sweepPendingOperations:)
                                                     userInfo:nil
                                                      repeats:YES];
}

- (void)sweepPendingOperations:(NSTimer *)timer {
    if (self.pending.count == 0) {
        [timer invalidate];
        self.sweepTimer = nil;
        return;
    }

    NSMutableArray<NSString *> *finished = [NSMutableArray array];

    for (MMShare *share in [MMStore shared].shares) {
        MMPendingOperation *op = self.pending[share.identifier];
        if (op == nil) continue;

        BOOL mounted = ([MMMounter mountPointForShare:share] != nil);
        if (![self operation:op settledWithMounted:mounted]) continue;

        BOOL gaveUp = (op.state == MMMountStateMounting && !mounted)
                   || (op.state == MMMountStateUnmounting && mounted);
        if (gaveUp) {
            NSLog(@"[MacMount] %@ não respondeu em %.0fs; liberando para nova tentativa.",
                  share.displayName, MMOperationTimeout);
        }
        [finished addObject:share.identifier];
    }

    // Entradas apagadas da lista enquanto a operação corria não aparecem no laço
    // acima e ficariam presas aqui para sempre.
    for (NSString *identifier in self.pending.allKeys) {
        if ([[MMStore shared] shareWithIdentifier:identifier] == nil) {
            [finished addObject:identifier];
        }
    }

    if (finished.count == 0) return;
    [self.pending removeObjectsForKeys:finished];
    [self notifyChanged];
}

#pragma mark - Ações

- (void)toggleShare:(MMShare *)share {
    switch ([self stateForShare:share]) {
        case MMMountStateMounted:   [self unmountShare:share]; break;
        case MMMountStateUnmounted: [self mountShare:share];   break;
        default: break;  // já está no meio de uma operação
    }
}

- (void)mountShare:(MMShare *)share {
    if ([self stateForShare:share] != MMMountStateUnmounted) return;

    NSString *problem = [share validationError];
    if (problem != nil) {
        [self reportTitle:NSLocalizedString(@"alert.cannotMount", @"Não foi possível montar")
                  message:problem];
        return;
    }

    NSUInteger generation = [self beginOperation:MMMountStateMounting forShare:share];

    NSString *password = share.savePassword ? [MMKeychain passwordForShare:share] : nil;
    // Com senha em mãos, tentamos sem interface. Sem senha, deixamos o diálogo
    // do sistema pedir — é o mesmo que o Finder faz.
    [self attemptMount:share password:password allowUI:(password.length == 0)
            generation:generation];
}

- (void)attemptMount:(MMShare *)share
            password:(nullable NSString *)password
             allowUI:(BOOL)allowUI
          generation:(NSUInteger)generation {

    // Se a montagem pode abrir o diálogo de credencial do sistema, o app precisa
    // estar à frente. Vivendo só na barra de menus, ou logo depois de um
    // reinício com tudo se restaurando, esse diálogo nasce atrás das outras
    // janelas — e o NetFS fica parado esperando uma resposta que ninguém vê.
    if (allowUI && !self.silent) [NSApp activateIgnoringOtherApps:YES];

    [MMMounter mountShare:share password:password allowUI:allowUI
               completion:^(NSString *_Nullable mountPoint, NSError *_Nullable error) {
        // Tentativa abandonada por tempo, e já substituída: o resultado chegou
        // tarde demais para mexer na tela ou falar com o usuário.
        if (![self isCurrentOperation:generation forShare:share]) {
            NSLog(@"[MacMount] resposta atrasada de %@ ignorada: %@", share.displayName,
                  error != nil ? error.localizedDescription : @"montou");
            return;
        }

        if (error == nil) {
            [self endOperation:generation forShare:share];
            return;
        }

        // Senha guardada recusada: repete deixando o sistema perguntar, em vez
        // de exigir que o usuário vá até as configurações trocar a senha. A
        // segunda tentativa herda o número da primeira, porque é a mesma
        // operação do ponto de vista de quem está olhando a lista.
        BOOL authFailed = (error.code == EAUTH || error.code == EACCES || error.code == EPERM);
        if (authFailed && !allowUI && !self.silent) {
            [self attemptMount:share password:nil allowUI:YES generation:generation];
            return;
        }

        [self endOperation:generation forShare:share];
        if (error.code != ECANCELED && error.code != -128) {
            [self reportTitle:[NSString stringWithFormat:
                               NSLocalizedString(@"alert.mountFailedFmt", @"Falha ao montar “%@”"),
                               share.displayName]
                      message:error.localizedDescription];
        }
    }];
}

- (void)unmountShare:(MMShare *)share {
    NSString *path = [MMMounter mountPointForShare:share];
    if (path == nil) return;

    NSUInteger generation = [self beginOperation:MMMountStateUnmounting forShare:share];

    [MMMounter unmountPath:path force:NO completion:^(NSError *_Nullable error) {
        if (![self isCurrentOperation:generation forShare:share]) return;
        [self endOperation:generation forShare:share];
        if (error == nil) return;

        if (self.silent) {
            NSLog(@"[MacMount] falha ao desmontar %@: %@", path, error.localizedDescription);
            return;
        }
        [self offerForcedUnmountOfShare:share path:path reason:error.localizedDescription];
    }];
}

/// Volume ocupado é o motivo mais comum de falha ao desmontar, e forçar resolve
/// — mas pode perder gravação pendente, então quem decide é o usuário.
- (void)offerForcedUnmountOfShare:(MMShare *)share path:(NSString *)path reason:(NSString *)reason {
    NSString *title = [NSString stringWithFormat:
                       NSLocalizedString(@"alert.unmountFailedFmt", @"Não foi possível desmontar “%@”"),
                       share.displayName];
    NSString *message = [NSString stringWithFormat:@"%@\n\n%@", reason,
                         NSLocalizedString(@"alert.forceHint",
                                           @"Forçar pode descartar gravações ainda não concluídas.")];

    if (!MMConfirmWarning(title, message, NSLocalizedString(@"alert.force", @"Forçar"))) return;

    NSUInteger generation = [self beginOperation:MMMountStateUnmounting forShare:share];

    [MMMounter unmountPath:path force:YES completion:^(NSError *_Nullable error) {
        if (![self isCurrentOperation:generation forShare:share]) return;
        [self endOperation:generation forShare:share];
        if (error != nil) {
            [self reportTitle:NSLocalizedString(@"alert.unmountFailed", @"Falha ao desmontar")
                      message:error.localizedDescription];
        }
    }];
}

/// A lista vem copiada do MMStore, então montar ou desmontar durante a iteração
/// — o que mexe no estado transitório — não invalida o que está sendo percorrido.
- (void)enumerateSharesInState:(MMMountState)state usingBlock:(void (^)(MMShare *share))block {
    for (MMShare *share in [MMStore shared].shares) {
        if ([self stateForShare:share] == state) block(share);
    }
}

- (void)mountAll {
    [self enumerateSharesInState:MMMountStateUnmounted usingBlock:^(MMShare *share) {
        [self mountShare:share];
    }];
}

- (void)unmountAll {
    [self enumerateSharesInState:MMMountStateMounted usingBlock:^(MMShare *share) {
        [self unmountShare:share];
    }];
}

- (BOOL)hasSharesInState:(MMMountState)state {
    for (MMShare *share in [MMStore shared].shares) {
        if ([self stateForShare:share] == state) return YES;
    }
    return NO;
}

- (void)mountFlaggedForLogin {
    [self enumerateSharesInState:MMMountStateUnmounted usingBlock:^(MMShare *share) {
        if (share.mountAtLogin) [self mountShare:share];
    }];
}

- (void)reconnectFlaggedSharesSilently {
    [self enumerateSharesInState:MMMountStateUnmounted usingBlock:^(MMShare *share) {
        if (!share.reconnect || [share validationError] != nil) return;

        // Só dá para tentar sem interface se houver credencial pronta. Sem
        // isso a montagem abriria o diálogo do sistema do nada, possivelmente
        // com a tela bloqueada ou o usuário longe da máquina.
        NSString *password = share.savePassword ? [MMKeychain passwordForShare:share] : nil;
        if (!share.guest && password.length == 0) return;

        NSUInteger generation = [self beginOperation:MMMountStateMounting forShare:share];

        [MMMounter mountShare:share password:password allowUI:NO
                   completion:^(NSString *_Nullable mountPoint, NSError *_Nullable error) {
            if (![self isCurrentOperation:generation forShare:share]) return;
            [self endOperation:generation forShare:share];
            if (error != nil) {
                // Silêncio é proposital: a rede pode ter voltado pela metade e
                // a próxima tentativa vem no próximo evento.
                NSLog(@"[MacMount] reconexão de %@ falhou: %@",
                      share.displayName, error.localizedDescription);
            }
        }];
    }];
}

- (BOOL)revealShareInFinder:(MMShare *)share {
    NSString *path = [MMMounter mountPointForShare:share];
    if (path == nil) return NO;
    // openURL: com file:// em vez de openFile:, que está obsoleto desde o
    // macOS 11 — e openURL: existe desde o 10.0, então não precisa de guarda.
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path isDirectory:YES]];
    return YES;
}

#pragma mark - Relato

- (void)reportTitle:(NSString *)title message:(NSString *)message {
    if (self.silent) {
        NSLog(@"[MacMount] %@: %@", title, message);
        return;
    }
    MMShowWarning(title, message, nil);
}

@end
