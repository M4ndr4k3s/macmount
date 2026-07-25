//
//  MMCoordinator.m
//

#import "MMCoordinator.h"

#import <AppKit/AppKit.h>

#include <errno.h>

#import "MMKeychain.h"
#import "MMMounter.h"
#import "MMStore.h"

NSString *const MMCoordinatorDidChangeNotification = @"MMCoordinatorDidChangeNotification";

@interface MMCoordinator ()
/// Só estados transitórios; "montado" é sempre perguntado ao sistema, nunca
/// guardado — assim o app não mente quando alguém desmonta pelo Finder.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *transient;
@end

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
    __weak typeof(self) weakSelf = self;
    [MMMounter mountShare:share password:password allowUI:allowUI
               completion:^(NSString *_Nullable mountPoint, NSError *_Nullable error) {
        typeof(self) self_ = weakSelf;
        if (self_ == nil) return;

        if (error == nil) {
            [self_ clearTransientStateForShare:share];
            return;
        }

        // Senha guardada recusada: repete deixando o sistema perguntar, em vez
        // de exigir que o usuário vá até as configurações trocar a senha.
        BOOL authFailed = (error.code == EAUTH || error.code == EACCES || error.code == EPERM);
        if (authFailed && !allowUI && !self_.silent) {
            [self_ attemptMount:share password:nil allowUI:YES];
            return;
        }

        [self_ clearTransientStateForShare:share];
        if (error.code != ECANCELED && error.code != -128) {
            [self_ reportTitle:[NSString stringWithFormat:
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

    __weak typeof(self) weakSelf = self;
    [MMMounter unmountPath:path force:NO completion:^(NSError *_Nullable error) {
        typeof(self) self_ = weakSelf;
        if (self_ == nil) return;

        if (error == nil) {
            [self_ clearTransientStateForShare:share];
            return;
        }

        [self_ clearTransientStateForShare:share];
        if (self_.silent) {
            NSLog(@"[MacMount] falha ao desmontar %@: %@", path, error.localizedDescription);
            return;
        }
        [self_ offerForcedUnmountOfShare:share path:path reason:error.localizedDescription];
    }];
}

/// Volume ocupado é o motivo mais comum de falha ao desmontar, e forçar resolve
/// — mas pode perder gravação pendente, então quem decide é o usuário.
- (void)offerForcedUnmountOfShare:(MMShare *)share path:(NSString *)path reason:(NSString *)reason {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = [NSString stringWithFormat:
                         NSLocalizedString(@"alert.unmountFailedFmt", @"Não foi possível desmontar “%@”"),
                         share.displayName];
    alert.informativeText = [NSString stringWithFormat:@"%@\n\n%@", reason,
                             NSLocalizedString(@"alert.forceHint",
                                               @"Forçar pode descartar gravações ainda não concluídas.")];
    [alert addButtonWithTitle:NSLocalizedString(@"alert.force", @"Forçar")];
    [alert addButtonWithTitle:NSLocalizedString(@"alert.cancel", @"Cancelar")];

    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    [self setTransientState:MMMountStateUnmounting forShare:share];

    __weak typeof(self) weakSelf = self;
    [MMMounter unmountPath:path force:YES completion:^(NSError *_Nullable error) {
        typeof(self) self_ = weakSelf;
        if (self_ == nil) return;
        [self_ clearTransientStateForShare:share];
        if (error != nil) {
            [self_ reportTitle:NSLocalizedString(@"alert.unmountFailed", @"Falha ao desmontar")
                       message:error.localizedDescription];
        }
    }];
}

- (void)mountAll {
    for (MMShare *share in [MMStore shared].shares) {
        if ([self stateForShare:share] == MMMountStateUnmounted) [self mountShare:share];
    }
}

- (void)mountFlaggedForLogin {
    for (MMShare *share in [MMStore shared].shares) {
        if (!share.mountAtLogin) continue;
        if ([self stateForShare:share] == MMMountStateUnmounted) [self mountShare:share];
    }
}

- (BOOL)revealShareInFinder:(MMShare *)share {
    NSString *path = [MMMounter mountPointForShare:share];
    if (path == nil) return NO;
    [[NSWorkspace sharedWorkspace] openFile:path];
    return YES;
}

#pragma mark - Relato

- (void)reportTitle:(NSString *)title message:(NSString *)message {
    if (self.silent) {
        NSLog(@"[MacMount] %@: %@", title, message);
        return;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = title;
    alert.informativeText = message;
    [alert addButtonWithTitle:NSLocalizedString(@"alert.ok", @"OK")];
    [alert runModal];
}

@end
