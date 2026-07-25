//
//  mount_smoke.m — monta um compartilhamento de verdade e desmonta.
//
//  Diferente de logic_tests.m, este exercita o NetFSMountURLSync contra um
//  servidor SMB real. No CI o servidor é um Samba levantado no próprio runner
//  (por isso o kNetFSAllowLoopbackKey no MMMounter); localmente serve para
//  apontar para um NAS ou um Windows da rede.
//
//  Uso: mount_smoke <url> [usuário] [senha] [arquivo-esperado]
//  Ex.: mount_smoke smb://localhost/teste ci senha123 ola.txt
//
//  Sai 0 se montou, encontrou o arquivo esperado (quando informado) e desmontou.
//

#import <Foundation/Foundation.h>

#import "MMMounter.h"
#import "MMShare.h"

/// Gira o run loop até o bloco terminar — as callbacks do MMMounter voltam na
/// fila principal, então bloquear a thread principal num semáforo travaria tudo.
static BOOL waitUntil(volatile BOOL *done, NSTimeInterval timeout) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!*done && [deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
    return *done;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "uso: mount_smoke <url> [usuário] [senha] [arquivo-esperado]\n");
            return 2;
        }

        MMShare *share = [MMShare shareWithUserInput:@(argv[1])];
        if (argc > 2 && strlen(argv[2]) > 0) share.username = @(argv[2]);
        NSString *password = (argc > 3 && strlen(argv[3]) > 0) ? @(argv[3]) : nil;
        NSString *expectedFile = (argc > 4 && strlen(argv[4]) > 0) ? @(argv[4]) : nil;
        share.savePassword = NO;

        NSString *problem = [share validationError];
        if (problem != nil) {
            fprintf(stderr, "entrada inválida: %s\n", problem.UTF8String);
            return 2;
        }

        fprintf(stdout, "montando %s ...\n", [share mountURL].absoluteString.UTF8String);

        __block NSString *mountPoint = nil;
        __block NSError *mountError = nil;
        __block volatile BOOL mounted = NO;

        [MMMounter mountShare:share password:password allowUI:NO
                   completion:^(NSString *point, NSError *error) {
            mountPoint = point;
            mountError = error;
            mounted = YES;
        }];

        if (!waitUntil(&mounted, 60.0)) {
            fprintf(stderr, "tempo esgotado esperando a montagem\n");
            return 1;
        }
        if (mountError != nil) {
            fprintf(stderr, "falha ao montar: %s\n", mountError.localizedDescription.UTF8String);
            return 1;
        }
        if (mountPoint.length == 0) {
            fprintf(stderr, "montagem relatou sucesso sem ponto de montagem\n");
            return 1;
        }
        fprintf(stdout, "montado em %s\n", mountPoint.UTF8String);

        int result = 0;

        // O caminho encontrado pelo getfsstat tem de bater com o que o NetFS
        // devolveu — é a mesma lógica que a interface usa para mostrar estado.
        NSString *detected = [MMMounter mountPointForShare:share];
        if (![detected isEqualToString:mountPoint]) {
            fprintf(stderr, "detecção divergiu: NetFS disse %s, getfsstat disse %s\n",
                    mountPoint.UTF8String, detected.UTF8String ?: "(nada)");
            result = 1;
        } else {
            fprintf(stdout, "detecção de estado confere\n");
        }

        if (expectedFile != nil) {
            NSString *path = [mountPoint stringByAppendingPathComponent:expectedFile];
            if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
                fprintf(stdout, "arquivo esperado encontrado: %s\n", expectedFile.UTF8String);
            } else {
                fprintf(stderr, "arquivo esperado ausente: %s\n", path.UTF8String);
                result = 1;
            }
        }

        __block NSError *unmountError = nil;
        __block volatile BOOL unmounted = NO;
        [MMMounter unmountPath:mountPoint force:NO completion:^(NSError *error) {
            unmountError = error;
            unmounted = YES;
        }];

        if (!waitUntil(&unmounted, 60.0)) {
            fprintf(stderr, "tempo esgotado esperando a desmontagem\n");
            return 1;
        }
        if (unmountError != nil) {
            fprintf(stderr, "falha ao desmontar: %s\n",
                    unmountError.localizedDescription.UTF8String);
            return 1;
        }
        fprintf(stdout, "desmontado\n");

        if ([MMMounter mountPointForShare:share] != nil) {
            fprintf(stderr, "ainda aparece montado depois de desmontar\n");
            result = 1;
        }

        return result;
    }
}
