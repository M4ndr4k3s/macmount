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

@interface MMCoordinator ()
/// Só estados transitórios; "montado" é sempre perguntado ao sistema, nunca
/// guardado — assim o app não mente quando alguém desmonta pelo Finder.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *transient;
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
        _transient = [NSMutableDictionary dictionary];
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

- (MMMountState)stateForShare:(MMShare *)share {
    NSNumber *pending = self.transient[share.identifier];
    if (pending != nil) return (MMMountState)pending.integerValue;
    return [MMMounter mountPointForShare:share] != nil ? MMMountStateMounted
                                                       : MMMountStateUnmounted;
}

- (nullable NSString *)mountPointForShare:(MMShare *)share {
    return [MMMounter mountPointForShare:share];
}

- (void)setTransientState:(MMMountState)state forShare:(MMShare *)share {
    self.transient[share.identifier] = @(state);
    [self notifyChanged];
}

- (BOOL)hasPendingOperations {
    return self.transient.count > 0;
}

- (void)clearTransientStateForShare:(MMShare *)share {
    [self.transient removeObjectForKey:share.identifier];
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

    [self setTransientState:MMMountStateMounting forShare:share];

    NSString *password = share.savePassword ? [MMKeychain passwordForShare:share] : nil;
    // Com senha em mãos, tentamos sem interface. Sem senha, deixamos o diálogo
    // do sistema pedir — é o mesmo que o Finder faz.
    [self attemptMount:share password:password allowUI:(password.length == 0)];
}

- (void)attemptMount:(MMShare *)share password:(nullable NSString *)password allowUI:(BOOL)allowUI {
    [MMMounter mountShare:share password:password allowUI:allowUI
               completion:^(NSString *_Nullable mountPoint, NSError *_Nullable error) {
        if (error == nil) {
            [self clearTransientStateForShare:share];
            return;
        }

        // Senha guardada recusada: repete deixando o sistema perguntar, em vez
        // de exigir que o usuário vá até as configurações trocar a senha.
        BOOL authFailed = (error.code == EAUTH || error.code == EACCES || error.code == EPERM);
        if (authFailed && !allowUI && !self.silent) {
            [self attemptMount:share password:nil allowUI:YES];
            return;
        }

        [self clearTransientStateForShare:share];
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
    if (path == nil) {
        [self clearTransientStateForShare:share];
        return;
    }

    [self setTransientState:MMMountStateUnmounting forShare:share];

    [MMMounter unmountPath:path force:NO completion:^(NSError *_Nullable error) {
        [self clearTransientStateForShare:share];
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

    [self setTransientState:MMMountStateUnmounting forShare:share];

    [MMMounter unmountPath:path force:YES completion:^(NSError *_Nullable error) {
        [self clearTransientStateForShare:share];
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

        [self setTransientState:MMMountStateMounting forShare:share];

        [MMMounter mountShare:share password:password allowUI:NO
                   completion:^(NSString *_Nullable mountPoint, NSError *_Nullable error) {
            [self clearTransientStateForShare:share];
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
