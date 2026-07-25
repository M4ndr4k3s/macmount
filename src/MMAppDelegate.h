//
//  MMAppDelegate.h
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MMAppDelegate : NSObject <NSApplicationDelegate>

/// Lançado pelo LaunchAgent: monta o que está marcado, sem interface, e encerra.
@property (nonatomic, assign) BOOL mountAtLoginMode;

/// Constrói janela e menu sem exibir, para o smoke test do CI. Retorna NO se
/// algo essencial não puder ser criado.
- (BOOL)runSmokeTest;

@end

NS_ASSUME_NONNULL_END
