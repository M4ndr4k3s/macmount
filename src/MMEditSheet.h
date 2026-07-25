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

@end

NS_ASSUME_NONNULL_END
