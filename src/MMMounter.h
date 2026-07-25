//
//  MMMounter.h — montar, desmontar e descobrir o que já está montado.
//
//  Usa NetFS.framework, a mesma API pública por trás do "Conectar ao servidor"
//  do Finder — não é wrapper de mount_smbfs.
//

#import <Foundation/Foundation.h>
#import "MMShare.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const MMMounterErrorDomain;

@interface MMMounter : NSObject

/// Monta em segundo plano; o bloco volta na fila principal.
/// `allowUI` YES deixa o sistema pedir credencial quando faltar senha.
+ (void)mountShare:(MMShare *)share
          password:(nullable NSString *)password
           allowUI:(BOOL)allowUI
        completion:(void (^)(NSString *_Nullable mountPoint, NSError *_Nullable error))completion;

/// Desmonta em segundo plano; o bloco volta na fila principal.
+ (void)unmountPath:(NSString *)path
              force:(BOOL)force
         completion:(void (^)(NSError *_Nullable error))completion;

/// Caminho em /Volumes se o compartilhamento já estiver montado, senão nil.
/// Seguro para chamar de qualquer fila (usa getfsstat com buffer próprio).
+ (nullable NSString *)mountPointForShare:(MMShare *)share;

/// Mensagem em português para um código do NetFSMountURLSync. Função pura.
+ (NSString *)messageForStatus:(int)status;

/// Casa o f_mntfromname de um volume montado com host+share configurados.
/// Função pura — é o coração da detecção de estado e o que os testes cobrem.
/// Exemplos de f_mntfromname reais: "//leandro@SERVIDOR/Publico",
/// "//GUEST@servidor._smb._tcp.local/Publico", "servidor:/export/dados".
+ (BOOL)mountFromName:(NSString *)fromName
          matchesHost:(NSString *)host
                share:(NSString *)sharePath;

@end

NS_ASSUME_NONNULL_END
