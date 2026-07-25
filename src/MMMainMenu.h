//
//  MMMainMenu.h — a barra de menus do topo da tela.
//
//  Fica montada mesmo com o ícone do Dock desligado, quando o sistema deixa de
//  exibi-la: é ela que faz Cmd+C e Cmd+V funcionarem nos campos de texto da
//  folha de edição. Os itens vão sem alvo de propósito, para o AppKit resolvê-los
//  pela cadeia de resposta — quem responde a "Adicionar compartilhamento…" é o
//  MMAppDelegate, e quem responde a Copiar é o campo em foco.
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MMMainMenu : NSObject

/// Constrói o menu e o instala em NSApp. Idempotente na prática: chamar de novo
/// simplesmente substitui o menu anterior.
+ (void)install;

@end

NS_ASSUME_NONNULL_END
