//
//  MMAlerts.h — os dois alertas que o app realmente usa.
//
//  Montar um NSAlert são cinco linhas iguais toda vez, e a quinta é sempre o
//  botão "OK". Espalhadas, elas viravam cinco chances de escrever um rótulo
//  diferente para o mesmo botão. Aqui ficam uma vez só.
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Aviso com um botão "OK". Com `window`, aparece como folha e a chamada
/// retorna na hora; sem ela, roda modal e só volta quando o usuário fecha.
extern void MMShowWarning(NSString *title, NSString *message, NSWindow *_Nullable window);

/// Pergunta de duas saídas, sempre modal — quem chama precisa da resposta para
/// decidir o que fazer em seguida. YES quando o usuário escolhe `confirmTitle`.
extern BOOL MMConfirmWarning(NSString *title, NSString *message, NSString *confirmTitle);

NS_ASSUME_NONNULL_END
