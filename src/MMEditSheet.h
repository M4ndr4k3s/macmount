//
//  MMEditSheet.h — folha de adicionar/editar compartilhamento.
//

#import <AppKit/AppKit.h>
#import "MMShare.h"

NS_ASSUME_NONNULL_BEGIN

@interface MMEditSheet : NSObject

/// `share` nil cria uma entrada nova. O bloco recebe a entrada salva, ou nil
/// se o usuário cancelar. Já grava no MMStore e no Keychain antes de chamar.
+ (void)presentForShare:(nullable MMShare *)share
               inWindow:(NSWindow *)parent
             completion:(void (^)(MMShare *_Nullable saved))completion;

/// Constrói a folha e devolve a janela, sem exibir nem prender a nada.
/// Existe para o `--smoke` do CI conseguir validar o formulário, que é o
/// layout mais frágil do app — e o único que ninguém vê antes de publicar.
+ (NSWindow *)buildSheetForSmokeTest;

@end

NS_ASSUME_NONNULL_END
