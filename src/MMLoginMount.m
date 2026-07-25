//
//  MMLoginMount.m
//

#import "MMLoginMount.h"

#import <AppKit/AppKit.h>

#import "MMCoordinator.h"
#import "MMPrefs.h"
#import "MMShare.h"
#import "MMStore.h"

/// Teto para a montagem automática do login: sem isso, um servidor sumido
/// deixaria o processo vivo para sempre esperando um soft mount desistir.
static NSTimeInterval const MMLoginMountTimeout = 120.0;

/// A notificação é entregue de forma assíncrona pelo sistema; encerrar no mesmo
/// ciclo de run loop a engoliria antes de ela aparecer na tela.
static NSTimeInterval const MMLoginMountNotificationGrace = 1.5;

@interface MMLoginMount ()
@property (nonatomic, strong, nullable) NSTimer *watchdog;
@property (nonatomic, strong, nullable) NSDate *startedAt;
@property (nonatomic, assign) NSUInteger target;
@property (nonatomic, copy, nullable) void (^completion)(void);
@end

@implementation MMLoginMount

- (void)startWithCompletion:(void (^)(void))completion {
    self.completion = completion;

    MMCoordinator *coordinator = [MMCoordinator shared];
    coordinator.silent = YES;

    self.target = [self flaggedShareCount];
    [coordinator mountFlaggedForLogin];

    self.startedAt = [NSDate date];
    self.watchdog = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                     target:self
                                                   selector:@selector(checkFinished:)
                                                   userInfo:nil
                                                    repeats:YES];
}

- (NSUInteger)flaggedShareCount {
    NSUInteger count = 0;
    for (MMShare *share in [MMStore shared].shares) {
        if (share.mountAtLogin) count++;
    }
    return count;
}

- (NSUInteger)mountedFlaggedShareCount {
    NSUInteger count = 0;
    for (MMShare *share in [MMStore shared].shares) {
        if (!share.mountAtLogin) continue;
        if ([[MMCoordinator shared] stateForShare:share] == MMMountStateMounted) count++;
    }
    return count;
}

- (void)checkFinished:(NSTimer *)timer {
    BOOL done = ![[MMCoordinator shared] hasPendingOperations];
    BOOL timedOut = [[NSDate date] timeIntervalSinceDate:self.startedAt] > MMLoginMountTimeout;

    if (timedOut && !done) {
        NSLog(@"[MacMount] montagem no login excedeu %.0fs; encerrando.", MMLoginMountTimeout);
    }
    if (!done && !timedOut) return;

    [timer invalidate];
    self.watchdog = nil;

    [self notifyResult];
    [self performSelector:@selector(finish)
               withObject:nil
               afterDelay:MMLoginMountNotificationGrace];
}

- (void)finish {
    void (^completion)(void) = self.completion;
    self.completion = nil;
    if (completion) completion();
}

/// Notificação nativa do 10.13. O UNUserNotificationCenter só existe do 10.14
/// em diante, então usar a API nova exigiria caminho duplo ou abandonar o
/// High Sierra — que é justamente o alvo deste app. O aviso de obsolescência
/// é silenciado de propósito.
- (void)notifyResult {
    if (!MMPrefs.notifyOnLoginMount || self.target == 0) return;

    NSUInteger mounted = [self mountedFlaggedShareCount];

    NSString *body;
    if (mounted == self.target) {
        body = (mounted == 1)
            ? NSLocalizedString(@"notify.oneMounted", @"1 compartilhamento montado.")
            : [NSString stringWithFormat:
               NSLocalizedString(@"notify.allMountedFmt", @"%lu compartilhamentos montados."),
               (unsigned long)mounted];
    } else {
        body = [NSString stringWithFormat:
                NSLocalizedString(@"notify.partialFmt", @"%lu de %lu compartilhamentos montados."),
                (unsigned long)mounted, (unsigned long)self.target];
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSUserNotification *note = [[NSUserNotification alloc] init];
    note.title = NSLocalizedString(@"app.name", @"MacMount");
    note.informativeText = body;
    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:note];
#pragma clang diagnostic pop
}

- (void)dealloc {
    [self.watchdog invalidate];
}

@end
