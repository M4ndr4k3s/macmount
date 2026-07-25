//
//  MMLoginItem.h — montar ao iniciar a sessão.
//
//  Usa um LaunchAgent em ~/Library/LaunchAgents. SMAppService só existe do
//  macOS 13 para cima e SMLoginItemSetEnabled exige um helper embutido no
//  bundle; o LaunchAgent é a única forma que cobre 10.13 até o 26 com um
//  mecanismo só.
//

#import <Foundation/Foundation.h>
#import "MMShare.h"

NS_ASSUME_NONNULL_BEGIN

/// Argumento passado ao app pelo LaunchAgent.
extern NSString *const MMMountAtLoginArgument;

@interface MMLoginItem : NSObject

@property (class, readonly, getter=isEnabled) BOOL enabled;

/// Instala ou remove o LaunchAgent. Retorna NO e preenche `error` se falhar.
+ (BOOL)setEnabled:(BOOL)enabled error:(NSError *_Nullable *_Nullable)error;

/// Regrava o plist se o app tiver mudado de lugar (ex.: movido para /Applications).
+ (void)refreshIfInstalled;

/// Instala o LaunchAgent se algum compartilhamento pede montagem no login, e o
/// remove se nenhum pede. Precisa ser chamado sempre que a lista muda — sem
/// isso a caixa "montar ao iniciar" fica marcada no arquivo e não faz nada.
+ (void)syncWithShares:(NSArray<MMShare *> *)shares;

@end

NS_ASSUME_NONNULL_END
