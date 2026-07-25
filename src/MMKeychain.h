//
//  MMKeychain.h — senhas no Keychain do usuário.
//
//  Grava como "internet password" com servidor/conta/protocolo/caminho, que é
//  exatamente o formato que o Finder usa no "Conectar ao servidor". Resultado:
//  a credencial é a mesma dos dois lados, em vez de duplicada.
//
//  A senha nunca é escrita no shares.json.
//

#import <Foundation/Foundation.h>
#import "MMShare.h"

NS_ASSUME_NONNULL_BEGIN

@interface MMKeychain : NSObject

/// Senha guardada, ou nil se não houver (ou se o usuário negar o acesso).
+ (nullable NSString *)passwordForShare:(MMShare *)share;

/// Grava ou atualiza. Senha vazia remove o item.
+ (BOOL)setPassword:(nullable NSString *)password
           forShare:(MMShare *)share
              error:(NSError *_Nullable *_Nullable)error;

+ (BOOL)removePasswordForShare:(MMShare *)share;

/// NO para protocolos sem autenticação por senha (NFS) ou entradas incompletas.
+ (BOOL)canStorePasswordForShare:(MMShare *)share;

@end

NS_ASSUME_NONNULL_END
