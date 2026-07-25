//
//  MMLoginItem.m
//

#import "MMLoginItem.h"

#include <unistd.h>

NSString *const MMMountAtLoginArgument = @"--mount-at-login";

static NSString *const MMLoginItemLabel = @"com.mdksoftware.macmount.login";
static NSString *const MMLoginItemErrorDomain = @"com.mdksoftware.macmount.loginitem";

@implementation MMLoginItem

+ (NSString *)plistPath {
    NSString *agents = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents"];
    return [agents stringByAppendingPathComponent:
            [MMLoginItemLabel stringByAppendingPathExtension:@"plist"]];
}

+ (BOOL)isEnabled {
    return [[NSFileManager defaultManager] fileExistsAtPath:[self plistPath]];
}

+ (NSDictionary *)agentDictionary {
    NSString *executable = [[NSBundle mainBundle] executablePath] ?: @"";
    return @{
        @"Label": MMLoginItemLabel,
        @"ProgramArguments": @[ executable, MMMountAtLoginArgument ],
        @"RunAtLoad": @YES,
        // Sem KeepAlive: o app monta o que precisa e decide sozinho se fica na
        // barra de menus ou encerra. Relançar em laço seria um pesadelo.
        @"ProcessType": @"Interactive",
    };
}

+ (BOOL)setEnabled:(BOOL)enabled error:(NSError *_Nullable *_Nullable)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *path = [self plistPath];

    if (!enabled) {
        [self runLaunchctl:@[ @"bootout", [self domainTarget] ] fallback:@[ @"unload", @"-w", path ]];
        if ([fm fileExistsAtPath:path]) {
            NSError *removeError = nil;
            if (![fm removeItemAtPath:path error:&removeError]) {
                if (error) *error = removeError;
                return NO;
            }
        }
        return YES;
    }

    NSString *executable = [[NSBundle mainBundle] executablePath];
    if (executable.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:MMLoginItemErrorDomain code:1 userInfo:@{
                NSLocalizedDescriptionKey:
                    NSLocalizedString(@"login.noExecutable",
                                      @"Não foi possível localizar o aplicativo.")
            }];
        }
        return NO;
    }

    NSString *folder = [path stringByDeletingLastPathComponent];
    if (![fm fileExistsAtPath:folder]) {
        [fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    }

    NSError *plistError = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:[self agentDictionary]
                                                              format:NSPropertyListXMLFormat_v1_0
                                                             options:0
                                                               error:&plistError];
    if (data == nil || ![data writeToFile:path options:NSDataWritingAtomic error:&plistError]) {
        if (error) *error = plistError;
        return NO;
    }

    // Recarrega para o launchd enxergar a versão nova sem exigir logout.
    [self runLaunchctl:@[ @"bootout", [self domainTarget] ] fallback:nil];
    [self runLaunchctl:@[ @"bootstrap", [self guiDomain], path ]
              fallback:@[ @"load", @"-w", path ]];
    return YES;
}

+ (void)refreshIfInstalled {
    if (![self isEnabled]) return;

    NSDictionary *onDisk = [NSDictionary dictionaryWithContentsOfFile:[self plistPath]];
    NSArray *current = onDisk[@"ProgramArguments"];
    NSArray *wanted = [self agentDictionary][@"ProgramArguments"];
    if ([current isEqualToArray:wanted]) return;

    [self setEnabled:YES error:NULL];
}

+ (void)syncWithShares:(NSArray<MMShare *> *)shares {
    BOOL wanted = NO;
    for (MMShare *share in shares) {
        if (share.mountAtLogin) { wanted = YES; break; }
    }

    if (wanted == [self isEnabled]) {
        // Já está no estado certo; só confere se o caminho do app mudou.
        if (wanted) [self refreshIfInstalled];
        return;
    }

    NSError *error = nil;
    if ([self setEnabled:wanted error:&error]) {
        NSLog(@"[MacMount] montagem no login %@", wanted ? @"ativada" : @"desativada");
    } else {
        NSLog(@"[MacMount] não foi possível %@ a montagem no login: %@",
              wanted ? @"ativar" : @"desativar",
              error.localizedDescription ?: @"motivo desconhecido");
    }
}

#pragma mark - launchctl

+ (NSString *)guiDomain {
    return [NSString stringWithFormat:@"gui/%u", getuid()];
}

+ (NSString *)domainTarget {
    return [NSString stringWithFormat:@"gui/%u/%@", getuid(), MMLoginItemLabel];
}

/// `bootstrap`/`bootout` existem desde o 10.11; `load`/`unload` ficam como rede
/// de segurança. Falha aqui não é fatal: o plist em disco basta para o próximo
/// login, que é o momento que realmente importa.
+ (void)runLaunchctl:(NSArray<NSString *> *)arguments
            fallback:(nullable NSArray<NSString *> *)fallback {
    if (![self launchctlWithArguments:arguments] && fallback != nil) {
        [self launchctlWithArguments:fallback];
    }
}

+ (BOOL)launchctlWithArguments:(NSArray<NSString *> *)arguments {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/launchctl"];
    task.arguments = arguments;
    task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    task.standardError = [NSFileHandle fileHandleWithNullDevice];

    NSError *err = nil;
    if (![task launchAndReturnError:&err]) return NO;

    [task waitUntilExit];
    return task.terminationStatus == 0;
}

@end
