//
//  MMReconnector.m
//

#import "MMReconnector.h"

#import <AppKit/AppKit.h>
#import <SystemConfiguration/SystemConfiguration.h>

#include <netinet/in.h>
#include <string.h>

#import "MMCoordinator.h"

/// Espera depois do gatilho antes de tentar montar. Rede recém-associada ainda
/// não roteia, e acordar do sono leva alguns segundos até o Wi-Fi voltar.
static NSTimeInterval const MMReconnectSettleDelay = 5.0;

/// Piso entre duas tentativas. Uma troca de rede dispara vários eventos de
/// alcançabilidade seguidos; sem isso o app metralharia o servidor.
static NSTimeInterval const MMReconnectMinimumInterval = 20.0;

@interface MMReconnector ()
@property (nonatomic, assign) SCNetworkReachabilityRef reachability;
@property (nonatomic, strong, nullable) NSTimer *settleTimer;
@property (nonatomic, strong, nullable) NSDate *lastAttempt;

// Declarado aqui porque a callback do SCNetworkReachability é uma função C
// fora da @implementation e não enxerga métodos definidos depois dela.
- (void)scheduleAttemptBecause:(NSString *)reason;
@end

static void MMReachabilityChanged(SCNetworkReachabilityRef target,
                                  SCNetworkReachabilityFlags flags,
                                  void *info) {
    (void)target;
    if ((flags & kSCNetworkReachabilityFlagsReachable) == 0) return;

    MMReconnector *reconnector = (__bridge MMReconnector *)info;
    [reconnector scheduleAttemptBecause:@"rede alcançável"];
}

@implementation MMReconnector

- (void)dealloc {
    [self stop];
}

- (void)start {
    if (self.reachability != NULL) return;

    [[[NSWorkspace sharedWorkspace] notificationCenter]
        addObserver:self
           selector:@selector(systemDidWake:)
               name:NSWorkspaceDidWakeNotification
             object:nil];

    // Endereço zerado: a pergunta é "existe rota para fora?", não "aquele
    // servidor responde?". Vigiar cada host daria mais precisão ao custo de um
    // watcher por entrada, e a tentativa de montar já é o teste real.
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;

    SCNetworkReachabilityRef ref =
        SCNetworkReachabilityCreateWithAddress(NULL, (const struct sockaddr *)&address);
    if (ref == NULL) {
        NSLog(@"[MacMount] não foi possível observar a rede; reconexão fica só no despertar");
        return;
    }

    SCNetworkReachabilityContext context = { 0, (__bridge void *)self, NULL, NULL, NULL };
    if (!SCNetworkReachabilitySetCallback(ref, MMReachabilityChanged, &context) ||
        !SCNetworkReachabilityScheduleWithRunLoop(ref, CFRunLoopGetMain(), kCFRunLoopCommonModes)) {
        CFRelease(ref);
        NSLog(@"[MacMount] não foi possível agendar o observador de rede");
        return;
    }

    self.reachability = ref;
}

- (void)stop {
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];

    [self.settleTimer invalidate];
    self.settleTimer = nil;

    if (self.reachability != NULL) {
        SCNetworkReachabilityUnscheduleFromRunLoop(self.reachability,
                                                   CFRunLoopGetMain(),
                                                   kCFRunLoopCommonModes);
        CFRelease(self.reachability);
        self.reachability = NULL;
    }
}

- (void)systemDidWake:(NSNotification *)note {
    (void)note;
    [self scheduleAttemptBecause:@"o Mac acordou"];
}

- (void)scheduleAttemptBecause:(NSString *)reason {
    // Já há uma tentativa a caminho: os eventos vêm em rajada e uma basta.
    if (self.settleTimer != nil) return;

    if (self.lastAttempt != nil &&
        [[NSDate date] timeIntervalSinceDate:self.lastAttempt] < MMReconnectMinimumInterval) {
        return;
    }

    NSLog(@"[MacMount] reconexão agendada (%@)", reason);
    self.settleTimer = [NSTimer scheduledTimerWithTimeInterval:MMReconnectSettleDelay
                                                        target:self
                                                      selector:@selector(runAttempt:)
                                                      userInfo:nil
                                                       repeats:NO];
}

- (void)runAttempt:(NSTimer *)timer {
    (void)timer;
    self.settleTimer = nil;
    self.lastAttempt = [NSDate date];
    [[MMCoordinator shared] reconnectFlaggedSharesSilently];
}

@end
