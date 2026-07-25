//
//  MMReconnector.h — remonta sozinho quando a rede volta ou o Mac acorda.
//
//  Observa dois sinais: acordar do sono (NSWorkspaceDidWakeNotification) e
//  mudança de alcançabilidade de rede (SCNetworkReachability, porque o Network
//  framework só existe do 10.14 em diante).
//
//  Age apenas sobre compartilhamentos marcados como "reconectar" e sempre em
//  silêncio — ver -[MMCoordinator reconnectFlaggedSharesSilently].
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MMReconnector : NSObject

- (void)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
