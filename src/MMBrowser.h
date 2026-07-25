//
//  MMBrowser.h — descoberta de servidores na rede local via Bonjour.
//
//  Alimenta as sugestões do campo "servidor". É opcional: o app funciona
//  inteiro digitando o nome ou o IP na mão.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MMDiscoveredServer : NSObject
@property (nonatomic, copy) NSString *displayName;   // "SERVIDOR"
@property (nonatomic, copy) NSString *hostname;      // "servidor.local"
@property (nonatomic, copy) NSString *serviceType;   // "_smb._tcp."
@end

@protocol MMBrowserDelegate <NSObject>
- (void)browserDidUpdateServers:(NSArray<MMDiscoveredServer *> *)servers;
@end

@interface MMBrowser : NSObject

@property (nonatomic, weak, nullable) id<MMBrowserDelegate> delegate;
@property (nonatomic, readonly) NSArray<MMDiscoveredServer *> *servers;

- (void)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
