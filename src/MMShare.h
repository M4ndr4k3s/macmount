//
//  MMShare.h — modelo de um compartilhamento de rede.
//
//  Tudo aqui é lógica pura (sem UI, sem rede): montagem de URL, normalização de
//  caminho e parsing do que o usuário cola no campo de servidor. É o arquivo que
//  test/logic_tests.m exercita, porque é onde mora a chance real de erro.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MMProtocol) {
    MMProtocolSMB = 0,   // Windows, Samba, NAS — o caso principal
    MMProtocolAFP = 1,   // Macs antigos e Time Capsule
    MMProtocolNFS = 2,   // Unix
    MMProtocolWebDAV = 3,
    MMProtocolWebDAVS = 4,
};

/// "smb", "afp", "nfs", "http", "https" — o esquema da URL passada ao NetFS.
extern NSString *MMProtocolScheme(MMProtocol proto);

/// Rótulo para a interface, já localizado.
extern NSString *MMProtocolDisplayName(MMProtocol proto);

/// Converte um esquema de URL em protocolo. Retorna NO se não reconhecer.
extern BOOL MMProtocolFromScheme(NSString *scheme, MMProtocol *outProto);

/// Ordem em que os protocolos aparecem no menu suspenso.
extern NSArray<NSNumber *> *MMAllProtocols(void);

@interface MMShare : NSObject <NSCopying>

@property (nonatomic, copy) NSString *identifier;          // UUID, estável entre sessões
@property (nonatomic, copy) NSString *name;                // rótulo escolhido pelo usuário
@property (nonatomic, assign) MMProtocol proto;
@property (nonatomic, copy) NSString *host;                // sem porta
@property (nonatomic, assign) NSInteger port;              // 0 = padrão do protocolo
@property (nonatomic, copy) NSString *sharePath;           // "Publico" ou "Publico/Docs"
@property (nonatomic, copy, nullable) NSString *username;

@property (nonatomic, assign) BOOL guest;                  // conectar como convidado
@property (nonatomic, assign) BOOL readOnly;               // MNT_RDONLY
@property (nonatomic, assign) BOOL hideOnDesktop;          // MNT_DONTBROWSE
@property (nonatomic, assign) BOOL mountAtLogin;
@property (nonatomic, assign) BOOL savePassword;           // guardar no Keychain

/// URL de montagem, ex.: smb://SERVIDOR/Publico%20Geral. nil se faltar servidor.
/// O usuário nunca entra na URL — vai separado para o NetFS.
- (nullable NSURL *)mountURL;

/// "Publico/Docs" — sem barras nas pontas, com "\" convertido em "/".
- (NSString *)normalizedSharePath;

/// Nome mostrado na lista: o rótulo, ou "servidor/share" se não houver rótulo.
- (NSString *)displayName;

/// Descrição do problema se a entrada estiver incompleta; nil se estiver válida.
- (nullable NSString *)validationError;

/// Interpreta o que o usuário digitou ou colou. Aceita, entre outros:
///   \\SERVIDOR\Publico\Sub   (caminho UNC do Windows, o formato mais comum)
///   //SERVIDOR/Publico
///   smb://usuario@SERVIDOR:445/Publico
///   afp://SERVIDOR/Media
///   SERVIDOR/Publico
///   SERVIDOR
/// Sempre devolve um objeto; use -validationError para saber se dá para montar.
+ (instancetype)shareWithUserInput:(NSString *)text;

+ (nullable instancetype)shareWithJSONObject:(NSDictionary *)obj;
- (NSDictionary *)JSONObject;

@end

NS_ASSUME_NONNULL_END
