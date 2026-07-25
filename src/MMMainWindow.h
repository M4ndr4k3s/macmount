//
//  MMMainWindow.h — janela com a lista de compartilhamentos.
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MMMainWindow : NSWindowController

@property (class, readonly) MMMainWindow *shared;

- (void)showAndActivate;

/// Abre a folha de novo compartilhamento (usada também pelo menu da barra).
- (void)addShare:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
