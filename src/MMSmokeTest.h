//
//  MMSmokeTest.h — a interface construída fora da tela, para o CI.
//
//  Nenhum desenvolvedor tem um Mac aqui: ninguém abre o app antes de publicar.
//  Este é o substituto possível — construir janela, menu e folha de edição sem
//  exibir nada e conferir que existem, cabem e estão ligados. Pega constraint
//  quebrada, crash de inicialização e fiação ausente, que é a classe de defeito
//  que os testes de lógica não alcançam.
//
//  Mora fora do MMAppDelegate de propósito: é andaime de teste, não parte do
//  ciclo de vida do app.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MMSmokeTest : NSObject

/// Roda todas as verificações, relatando cada uma na saída padrão.
/// NO se alguma falhar. Exige uma sessão gráfica (quem chama confere isso).
+ (BOOL)run;

@end

NS_ASSUME_NONNULL_END
