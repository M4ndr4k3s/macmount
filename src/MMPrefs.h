//
//  MMPrefs.h — preferências do app, em NSUserDefaults.
//
//  Só ajustes globais. O que é por compartilhamento mora no MMShare e vai para
//  o shares.json.
//
//  Chaves gravadas (domínio com.mdksoftware.macmount):
//    MMShowDockIcon        BOOL, padrão YES
//    MMNotifyOnLoginMount  BOOL, padrão YES
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

@end

NS_ASSUME_NONNULL_END
