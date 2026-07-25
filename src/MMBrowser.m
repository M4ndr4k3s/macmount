//
//  MMBrowser.m
//

#import "MMBrowser.h"

// NSNetService está marcado como obsoleto no macOS 15 em favor do Network
// framework, que só existe do 10.14 para cima. Como o piso do app é 10.13,
// NSNetService é a única opção disponível — o aviso é silenciado de propósito.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@implementation MMDiscoveredServer

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[MMDiscoveredServer class]]) return NO;
    MMDiscoveredServer *o = object;
    return [self.displayName isEqualToString:o.displayName]
        && [self.serviceType isEqualToString:o.serviceType];
}

- (NSUInteger)hash {
    return self.displayName.hash ^ self.serviceType.hash;
}

@end

#pragma mark -

@interface MMBrowser () <NSNetServiceBrowserDelegate, NSNetServiceDelegate>
@property (nonatomic, strong) NSMutableArray<NSNetServiceBrowser *> *browsers;
@property (nonatomic, strong) NSMutableArray<NSNetService *> *resolving;
@property (nonatomic, strong) NSMutableArray<MMDiscoveredServer *> *found;
@end

@implementation MMBrowser

- (instancetype)init {
    self = [super init];
    if (self) {
        _browsers = [NSMutableArray array];
        _resolving = [NSMutableArray array];
        _found = [NSMutableArray array];
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (NSArray<MMDiscoveredServer *> *)servers {
    return [self.found copy];
}

- (void)start {
    if (self.browsers.count > 0) return;

    for (NSString *type in @[ @"_smb._tcp.", @"_afpovertcp._tcp." ]) {
        NSNetServiceBrowser *b = [[NSNetServiceBrowser alloc] init];
        b.delegate = self;
        [b searchForServicesOfType:type inDomain:@"local."];
        [self.browsers addObject:b];
    }
}

- (void)stop {
    for (NSNetServiceBrowser *b in self.browsers) {
        b.delegate = nil;
        [b stop];
    }
    [self.browsers removeAllObjects];

    for (NSNetService *s in self.resolving) {
        s.delegate = nil;
        [s stop];
    }
    [self.resolving removeAllObjects];
}

- (void)notifyChanged {
    [self.found sortUsingComparator:^NSComparisonResult(MMDiscoveredServer *a, MMDiscoveredServer *b) {
        return [a.displayName localizedCaseInsensitiveCompare:b.displayName];
    }];
    [self.delegate browserDidUpdateServers:[self.found copy]];
}

#pragma mark - NSNetServiceBrowserDelegate

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
           didFindService:(NSNetService *)service
               moreComing:(BOOL)moreComing {
    service.delegate = self;
    [self.resolving addObject:service];
    [service resolveWithTimeout:5.0];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
         didRemoveService:(NSNetService *)service
               moreComing:(BOOL)moreComing {
    MMDiscoveredServer *gone = [[MMDiscoveredServer alloc] init];
    gone.displayName = service.name;
    gone.serviceType = service.type;

    NSUInteger index = [self.found indexOfObject:gone];
    if (index != NSNotFound) [self.found removeObjectAtIndex:index];
    if (!moreComing) [self notifyChanged];
}

#pragma mark - NSNetServiceDelegate

- (void)netServiceDidResolveAddress:(NSNetService *)service {
    [self addServerForService:service];
    [self finishResolving:service];
}

- (void)netService:(NSNetService *)service didNotResolve:(NSDictionary<NSString *, NSNumber *> *)errorDict {
    // Sem resolução ainda dá para sugerir: o nome do serviço mais ".local"
    // costuma ser resolvível pelo próprio mDNS na hora de montar.
    [self addServerForService:service];
    [self finishResolving:service];
}

- (void)addServerForService:(NSNetService *)service {
    MMDiscoveredServer *server = [[MMDiscoveredServer alloc] init];
    server.displayName = service.name;
    server.serviceType = service.type;

    NSString *host = service.hostName;
    while ([host hasSuffix:@"."]) host = [host substringToIndex:host.length - 1];
    server.hostname = host.length > 0 ? host : service.name;

    if (![self.found containsObject:server]) [self.found addObject:server];
    [self notifyChanged];
}

- (void)finishResolving:(NSNetService *)service {
    service.delegate = nil;
    [self.resolving removeObject:service];
}

@end

#pragma clang diagnostic pop
