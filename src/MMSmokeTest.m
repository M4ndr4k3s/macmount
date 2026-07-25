//
//  MMSmokeTest.m
//

#import "MMSmokeTest.h"

#import <AppKit/AppKit.h>

#import "MMEditSheet.h"
#import "MMLoginItem.h"
#import "MMMainMenu.h"
#import "MMMainWindow.h"
#import "MMShare.h"
#import "MMStatusMenu.h"
#import "MMStore.h"

@implementation MMSmokeTest

+ (BOOL)run {
    BOOL ok = YES;

    if (![self checkMainMenu]) ok = NO;
    [self exerciseStatusMenu];
    if (![self checkMainWindow]) ok = NO;
    if (![self checkEditSheet]) ok = NO;
    if (![self checkModelAndStore]) ok = NO;
    if (![self checkLoginItemWiring]) ok = NO;

    if (ok) fprintf(stdout, "smoke: interface construída sem erros\n");
    return ok;
}

+ (BOOL)checkMainMenu {
    [MMMainMenu install];
    if (NSApp.mainMenu.numberOfItems >= 3) return YES;

    fprintf(stderr, "smoke: menu principal incompleto\n");
    return NO;
}

/// Instalar e remover já basta: o que pode dar errado aqui é o desenho do ícone
/// da barra, e ele acontece na instalação.
+ (void)exerciseStatusMenu {
    MMStatusMenu *status = [[MMStatusMenu alloc] init];
    [status install];
    [status remove];
}

+ (BOOL)checkMainWindow {
    MMMainWindow *window = [MMMainWindow shared];
    if (window.window == nil) {
        fprintf(stderr, "smoke: janela principal não foi criada\n");
        return NO;
    }
    // Força o layout sem exibir: é aqui que constraint quebrada aparece.
    [window.window.contentView layoutSubtreeIfNeeded];
    return YES;
}

/// A folha de edição é o formulário mais denso do app e a sua altura vem do
/// conteúdo, não de um número fixo — acrescentar uma linha e cortar os botões
/// seria fácil, e ninguém abre essa tela antes de publicar.
+ (BOOL)checkEditSheet {
    NSWindow *sheet = [MMEditSheet buildSheetForSmokeTest];
    if (sheet == nil) {
        fprintf(stderr, "smoke: folha de edição não foi criada\n");
        return NO;
    }

    NSSize size = sheet.frame.size;
    NSSize fitting = [sheet.contentView fittingSize];
    if (size.height + 1.0 < fitting.height || size.width + 1.0 < fitting.width) {
        fprintf(stderr, "smoke: folha menor que o conteúdo (%.0fx%.0f para caber %.0fx%.0f)\n",
                size.width, size.height, fitting.width, fitting.height);
        return NO;
    }

    fprintf(stdout, "smoke: folha de edição %.0fx%.0f comporta o formulário\n",
            size.width, size.height);
    return YES;
}

+ (BOOL)checkModelAndStore {
    BOOL ok = YES;

    MMShare *sample = [MMShare shareWithUserInput:@"\\\\SERVIDOR\\Publico"];
    if (![sample.host isEqualToString:@"SERVIDOR"]) {
        fprintf(stderr, "smoke: parser de UNC devolveu host inesperado: %s\n",
                sample.host.UTF8String);
        ok = NO;
    }

    if ([MMStore shared] == nil) {
        fprintf(stderr, "smoke: store não inicializou\n");
        ok = NO;
    }
    return ok;
}

/// A montagem no login já quebrou uma vez do jeito mais silencioso possível: a
/// caixa gravava a marca no shares.json e nada instalava o LaunchAgent, então
/// não havia erro nenhum para observar — apenas nada acontecia. Nenhum teste de
/// lógica pegaria isso, porque o defeito era a ausência de uma chamada.
///
/// Este exercício vai da lista até o arquivo em disco. Só roda quando não há
/// agente instalado, para nunca mexer na configuração de quem realmente usa.
+ (BOOL)checkLoginItemWiring {
    if (MMLoginItem.isEnabled) {
        fprintf(stdout, "smoke: já há um agente de login instalado; verificação pulada\n");
        return YES;
    }

    MMShare *flagged = [MMShare shareWithUserInput:@"smb://SERVIDOR/Publico"];
    flagged.mountAtLogin = YES;

    [MMLoginItem syncWithShares:@[ flagged ]];
    BOOL installed = MMLoginItem.isEnabled;

    [MMLoginItem syncWithShares:@[]];
    BOOL removed = !MMLoginItem.isEnabled;

    if (!installed) {
        fprintf(stderr, "smoke: entrada marcada para o login não instalou o LaunchAgent\n");
        return NO;
    }
    if (!removed) {
        fprintf(stderr, "smoke: LaunchAgent sobreviveu à remoção da última entrada de login\n");
        return NO;
    }

    fprintf(stdout, "smoke: LaunchAgent instala e remove conforme a lista\n");
    return YES;
}

@end
