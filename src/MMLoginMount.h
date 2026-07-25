//
//  MMLoginMount.h — o modo --mount-at-login, do começo ao fim.
//
//  Lançado pelo LaunchAgent no início da sessão. Monta o que está marcado, sem
//  interface e sem janela, avisa por notificação e devolve o controle para quem
//  chamou encerrar. É um processo de vida curta com relógio próprio: um servidor
//  sumido não pode deixá-lo vivo para sempre esperando o soft mount desistir.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MMLoginMount : NSObject

/// Começa a montagem e volta na hora — o trabalho corre pela fila principal.
/// `completion` é chamado uma única vez, quando não há mais nada pendente ou
/// quando o teto de tempo estoura, e já depois da notificação ter saído.
- (void)startWithCompletion:(void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
