//
//  MMAppDelegate.h
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MMAppDelegate : NSObject <NSApplicationDelegate>

/// Lançado pelo LaunchAgent: monta o que está marcado, sem interface, e encerra.
/// O trabalho em si é do MMLoginMount; aqui a marca só decide o caminho a tomar
/// e mantém a janela fechada até o processo terminar.
@property (nonatomic, assign) BOOL mountAtLoginMode;

@end

NS_ASSUME_NONNULL_END
