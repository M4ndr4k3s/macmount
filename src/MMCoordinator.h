//
//  MMCoordinator.h — estado de montagem, num lugar só.
//
//  A janela e o menu da barra são duas visões do mesmo estado; toda a decisão
//  de montar, buscar senha no Keychain e relatar erro mora aqui para não existir
//  em duplicata nos dois.
//

#import <Foundation/Foundation.h>
#import "MMShare.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MMMountState) {
    MMMountStateUnmounted = 0,
    MMMountStateMounting,
    MMMountStateMounted,
    MMMountStateUnmounting,
};

/// Postada na fila principal quando qualquer estado muda.
extern NSString *const MMCoordinatorDidChangeNotification;

@interface MMCoordinator : NSObject

@property (class, readonly) MMCoordinator *shared;

/// Em YES, erros vão só para o log — usado na montagem automática do login,
/// onde um alerta modal apareceria sem ninguém para ler.
@property (nonatomic, assign) BOOL silent;

- (MMMountState)stateForShare:(MMShare *)share;
- (nullable NSString *)mountPointForShare:(MMShare *)share;

- (void)mountShare:(MMShare *)share;
- (void)unmountShare:(MMShare *)share;
- (void)toggleShare:(MMShare *)share;

/// Monta tudo que ainda não está montado.
- (void)mountAll;

/// Monta só o que está marcado como "montar ao iniciar".
- (void)mountFlaggedForLogin;

/// Abre o volume montado no Finder. NO se não estiver montado.
- (BOOL)revealShareInFinder:(MMShare *)share;

/// Começa a observar montagens feitas fora do app (Finder, terminal).
- (void)startObservingVolumes;

/// YES enquanto houver montagem ou desmontagem em andamento.
- (BOOL)hasPendingOperations;

@end

NS_ASSUME_NONNULL_END
