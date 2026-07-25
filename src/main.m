//
//  main.m — ponto de entrada.
//
//  Três modos:
//    (sem argumento)      app normal, com janela e ícone na barra
//    --mount-at-login     lançado pelo LaunchAgent: monta em silêncio e encerra
//    --smoke              constrói a interface fora da tela e sai; usado pelo CI
//

#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>

#import "MMAppDelegate.h"
#import "MMLoginItem.h"
#import "MMSmokeTest.h"

// NSApplication mantém o delegate como referência fraca; guardar em variável
// local deixaria o ARC liberá-lo logo após a última menção.
static MMAppDelegate *gDelegate = nil;

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        BOOL smoke = NO;
        BOOL loginMode = NO;

        for (int i = 1; i < argc; i++) {
            NSString *arg = @(argv[i]);
            if ([arg isEqualToString:@"--smoke"]) {
                smoke = YES;
            } else if ([arg isEqualToString:MMMountAtLoginArgument]) {
                loginMode = YES;
            }
        }

        if (smoke) {
            // Sem sessão gráfica (runner headless), instanciar NSApplication
            // aborta o processo. Detectar antes evita um falso negativo no CI.
            CFDictionaryRef session = CGSessionCopyCurrentDictionary();
            if (session == NULL) {
                fprintf(stdout, "smoke: sem sessão gráfica disponível; teste pulado\n");
                return 0;
            }
            CFRelease(session);

            NSApplication *app = [NSApplication sharedApplication];
            [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
            return [MMSmokeTest run] ? 0 : 1;
        }

        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:(loginMode ? NSApplicationActivationPolicyAccessory
                                            : NSApplicationActivationPolicyRegular)];

        gDelegate = [[MMAppDelegate alloc] init];
        gDelegate.mountAtLoginMode = loginMode;
        app.delegate = gDelegate;

        [app run];
    }
    return 0;
}
