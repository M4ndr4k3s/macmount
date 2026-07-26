//
//  MMPrefs.h — preferências do app, em NSUserDefaults.
//
//  Só ajustes globais. O que é por compartilhamento mora no MMShare e vai para
//  o shares.json.
//
//  Chaves gravadas (domínio com.mdksoftware.macmount):
//    MMShowDockIcon        BOOL, padrão YES
//    MMNotifyOnLoginMount  BOOL, padrão YES
//    MMForceDarkMode       BOOL, padrão YES
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Postada na fila principal quando uma preferência muda.
extern NSString *const MMPrefsDidChangeNotification;

@interface MMPrefs : NSObject

/// Ícone no Dock. Desligado, o app vive só na barra de menus.
@property (class, nonatomic, assign) BOOL showDockIcon;

/// Avisar por notificação quando a montagem automática do login terminar.
@property (class, nonatomic, assign) BOOL notifyOnLoginMount;

/// Forçar interface escura independente do tema do sistema.
/// Só tem efeito no macOS 10.14+; no High Sierra não existe modo escuro.
@property (class, nonatomic, assign) BOOL forceDarkMode;

@end

NS_ASSUME_NONNULL_END
