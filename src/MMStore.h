//
//  MMStore.h — lista de compartilhamentos em disco.
//
//  ~/Library/Application Support/MacMount/shares.json, permissão 0600.
//  Só metadados: senha nenhuma passa por aqui (ver MMKeychain).
//

#import <Foundation/Foundation.h>
#import "MMShare.h"

NS_ASSUME_NONNULL_BEGIN

/// Postada na fila principal sempre que a lista muda.
extern NSString *const MMStoreDidChangeNotification;

@interface MMStore : NSObject

@property (class, readonly) MMStore *shared;

@property (nonatomic, readonly) NSArray<MMShare *> *shares;

- (void)addShare:(MMShare *)share;
- (void)updateShare:(MMShare *)share;      // casa pelo identifier
- (void)removeShareWithIdentifier:(NSString *)identifier;
- (nullable MMShare *)shareWithIdentifier:(NSString *)identifier;
- (void)moveShareFromIndex:(NSUInteger)from toIndex:(NSUInteger)to;

/// Recarrega do disco. Chamado no início; útil se o arquivo for editado à mão.
- (void)reload;

/// Grava agora. As mutações acima já gravam sozinhas.
- (BOOL)save;

@property (nonatomic, readonly) NSString *storePath;

@end

NS_ASSUME_NONNULL_END
