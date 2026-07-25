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

/// Converte o índice de drop da NSTableView no índice de inserção real, já
/// descontando a remoção do item de origem. Arrastar a linha 0 para "depois da
/// linha 2" chega aqui como dropIndex 3 e sai como 2.
///
/// Devolve NSNotFound quando o movimento é inválido ou não muda nada — o que
/// inclui soltar o item exatamente onde ele já estava (dropIndex == from e
/// dropIndex == from + 1). Função pura, coberta por test/logic_tests.m.
extern NSUInteger MMDestinationIndexForMove(NSUInteger from, NSUInteger dropIndex, NSUInteger count);

@interface MMStore : NSObject

@property (class, readonly) MMStore *shared;

@property (nonatomic, readonly) NSArray<MMShare *> *shares;

- (void)addShare:(MMShare *)share;
- (void)updateShare:(MMShare *)share;      // casa pelo identifier
- (void)removeShareWithIdentifier:(NSString *)identifier;
- (nullable MMShare *)shareWithIdentifier:(NSString *)identifier;
/// Reordena. `dropIndex` segue a convenção da NSTableView: é a posição de
/// inserção medida na lista **antes** de o item sair de `from`, então arrastar
/// para baixo produz um dropIndex maior que o destino final. Ver
/// MMDestinationIndexForMove.
- (void)moveShareFromIndex:(NSUInteger)from toDropIndex:(NSUInteger)dropIndex;

/// Recarrega do disco. Chamado no início; útil se o arquivo for editado à mão.
- (void)reload;

/// Grava agora. As mutações acima já gravam sozinhas.
- (BOOL)save;

@property (nonatomic, readonly) NSString *storePath;

@end

NS_ASSUME_NONNULL_END
