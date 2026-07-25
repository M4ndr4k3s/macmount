//
//  MMStore.m
//

#import "MMStore.h"

NSString *const MMStoreDidChangeNotification = @"MMStoreDidChangeNotification";

static NSString *const MMStoreFolderName = @"MacMount";
static NSString *const MMStoreFileName = @"shares.json";
static NSInteger const MMStoreFormatVersion = 1;

@interface MMStore ()
@property (nonatomic, strong) NSMutableArray<MMShare *> *mutableShares;
@end

@implementation MMStore

+ (MMStore *)shared {
    static MMStore *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[MMStore alloc] init]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableShares = [NSMutableArray array];
        [self reload];
    }
    return self;
}

- (NSArray<MMShare *> *)shares {
    return [self.mutableShares copy];
}

#pragma mark - Caminho

- (NSString *)storeFolder {
    NSArray<NSString *> *dirs = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *base = dirs.firstObject
        ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"];
    return [base stringByAppendingPathComponent:MMStoreFolderName];
}

- (NSString *)storePath {
    return [[self storeFolder] stringByAppendingPathComponent:MMStoreFileName];
}

#pragma mark - Ler e gravar

- (void)reload {
    [self.mutableShares removeAllObjects];

    NSData *data = [NSData dataWithContentsOfFile:[self storePath]];
    if (data.length == 0) return;

    NSError *err = nil;
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (![root isKindOfClass:[NSDictionary class]]) {
        NSLog(@"[MacMount] shares.json ilegível: %@", err.localizedDescription ?: @"formato inesperado");
        return;
    }

    id list = root[@"shares"];
    if (![list isKindOfClass:[NSArray class]]) return;

    for (id item in (NSArray *)list) {
        MMShare *s = [MMShare shareWithJSONObject:item];
        if (s != nil) [self.mutableShares addObject:s];
    }
}

- (BOOL)save {
    NSMutableArray *list = [NSMutableArray arrayWithCapacity:self.mutableShares.count];
    for (MMShare *s in self.mutableShares) [list addObject:[s JSONObject]];

    NSDictionary *root = @{ @"v": @(MMStoreFormatVersion), @"shares": list };

    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:root
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:&err];
    if (data == nil) {
        NSLog(@"[MacMount] falha ao serializar shares.json: %@", err.localizedDescription);
        return NO;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *folder = [self storeFolder];
    if (![fm fileExistsAtPath:folder]) {
        [fm createDirectoryAtPath:folder
      withIntermediateDirectories:YES
                       attributes:@{ NSFilePosixPermissions: @(0700) }
                            error:NULL];
    }

    NSString *path = [self storePath];
    if (![data writeToFile:path options:NSDataWritingAtomic error:&err]) {
        NSLog(@"[MacMount] falha ao gravar shares.json: %@", err.localizedDescription);
        return NO;
    }
    // A escrita atômica cria um arquivo novo, então a permissão é reaplicada.
    [fm setAttributes:@{ NSFilePosixPermissions: @(0600) } ofItemAtPath:path error:NULL];

    return YES;
}

- (void)commit {
    [self save];
    [[NSNotificationCenter defaultCenter] postNotificationName:MMStoreDidChangeNotification
                                                        object:self];
}

#pragma mark - Mutações

- (void)addShare:(MMShare *)share {
    if (share == nil) return;
    [self.mutableShares addObject:share];
    [self commit];
}

- (void)updateShare:(MMShare *)share {
    if (share == nil) return;
    NSUInteger index = [self indexOfIdentifier:share.identifier];
    if (index == NSNotFound) {
        [self.mutableShares addObject:share];
    } else {
        self.mutableShares[index] = share;
    }
    [self commit];
}

- (void)removeShareWithIdentifier:(NSString *)identifier {
    NSUInteger index = [self indexOfIdentifier:identifier];
    if (index == NSNotFound) return;
    [self.mutableShares removeObjectAtIndex:index];
    [self commit];
}

- (nullable MMShare *)shareWithIdentifier:(NSString *)identifier {
    NSUInteger index = [self indexOfIdentifier:identifier];
    return index == NSNotFound ? nil : self.mutableShares[index];
}

- (void)moveShareFromIndex:(NSUInteger)from toIndex:(NSUInteger)to {
    if (from >= self.mutableShares.count || to > self.mutableShares.count) return;
    MMShare *s = self.mutableShares[from];
    [self.mutableShares removeObjectAtIndex:from];
    [self.mutableShares insertObject:s atIndex:MIN(to, self.mutableShares.count)];
    [self commit];
}

- (NSUInteger)indexOfIdentifier:(NSString *)identifier {
    if (identifier.length == 0) return NSNotFound;
    for (NSUInteger i = 0; i < self.mutableShares.count; i++) {
        if ([self.mutableShares[i].identifier isEqualToString:identifier]) return i;
    }
    return NSNotFound;
}

@end
