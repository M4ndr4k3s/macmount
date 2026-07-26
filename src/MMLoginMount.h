//
//  MMLoginMount.h — a montagem automática do início da sessão.
//
//  Roda quando o app é aberto pelo LaunchAgent ou pelos Itens de Início: monta
//  o que está marcado, sem interface e sem janela, e avisa por notificação.
//
//  Até a v0.3.1 o processo encerrava depois disso. Não encerra mais: o app fica
//  na barra de menus, porque quem encerra perde o MMReconnector — e é justamente
//  no início da sessão, com a rede ainda subindo, que a primeira tentativa mais
//  falha e uma segunda mais adianta.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MMLoginMount : NSObject

/// Começa a montagem e volta na hora — o trabalho corre pela fila principal.
/// `completion` é chamado uma única vez, quando não há mais nada pendente ou
/// quando o teto de tempo estoura, e já depois da notificação ter saído. É o
/// gancho para o app voltar ao modo normal, em que erro vira alerta na tela.
- (void)startWithCompletion:(void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
