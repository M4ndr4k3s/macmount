//
//  MMShare.m
//

#import "MMShare.h"

NSString *MMProtocolScheme(MMProtocol proto) {
    switch (proto) {
        case MMProtocolAFP:      return @"afp";
        case MMProtocolNFS:      return @"nfs";
        case MMProtocolWebDAV:   return @"http";
        case MMProtocolWebDAVS:  return @"https";
        case MMProtocolSMB:
        default:                 return @"smb";
    }
}

NSString *MMProtocolDisplayName(MMProtocol proto) {
    switch (proto) {
        case MMProtocolAFP:      return NSLocalizedString(@"proto.afp", @"AFP");
        case MMProtocolNFS:      return NSLocalizedString(@"proto.nfs", @"NFS");
        case MMProtocolWebDAV:   return NSLocalizedString(@"proto.webdav", @"WebDAV");
        case MMProtocolWebDAVS:  return NSLocalizedString(@"proto.webdavs", @"WebDAV (HTTPS)");
        case MMProtocolSMB:
        default:                 return NSLocalizedString(@"proto.smb", @"SMB");
    }
}

BOOL MMProtocolFromScheme(NSString *scheme, MMProtocol *outProto) {
    NSString *s = scheme.lowercaseString;
    MMProtocol p;
    if ([s isEqualToString:@"smb"] || [s isEqualToString:@"cifs"]) {
        p = MMProtocolSMB;
    } else if ([s isEqualToString:@"afp"]) {
        p = MMProtocolAFP;
    } else if ([s isEqualToString:@"nfs"]) {
        p = MMProtocolNFS;
    } else if ([s isEqualToString:@"http"] || [s isEqualToString:@"webdav"]) {
        p = MMProtocolWebDAV;
    } else if ([s isEqualToString:@"https"] || [s isEqualToString:@"webdavs"]) {
        p = MMProtocolWebDAVS;
    } else {
        return NO;
    }
    if (outProto) *outProto = p;
    return YES;
}

NSArray<NSNumber *> *MMAllProtocols(void) {
    return @[ @(MMProtocolSMB), @(MMProtocolAFP), @(MMProtocolNFS),
              @(MMProtocolWebDAV), @(MMProtocolWebDAVS) ];
}

#pragma mark -

@implementation MMShare

- (instancetype)init {
    self = [super init];
    if (self) {
        _identifier = [[NSUUID UUID] UUIDString];
        _name = @"";
        _proto = MMProtocolSMB;
        _host = @"";
        _sharePath = @"";
        _savePassword = YES;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    MMShare *c = [[MMShare allocWithZone:zone] init];
    c->_identifier = [_identifier copy];
    c->_name = [_name copy];
    c->_proto = _proto;
    c->_host = [_host copy];
    c->_port = _port;
    c->_sharePath = [_sharePath copy];
    c->_username = [_username copy];
    c->_guest = _guest;
    c->_readOnly = _readOnly;
    c->_hideOnDesktop = _hideOnDesktop;
    c->_mountAtLogin = _mountAtLogin;
    c->_savePassword = _savePassword;
    return c;
}

#pragma mark - Caminho e URL

- (NSString *)normalizedSharePath {
    NSString *p = self.sharePath ?: @"";
    p = [p stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *c in [p componentsSeparatedByString:@"/"]) {
        NSString *t = [c stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceCharacterSet]];
        if (t.length > 0) [parts addObject:t];
    }
    return [parts componentsJoinedByString:@"/"];
}

- (nullable NSURL *)mountURL {
    if (self.host.length == 0) return nil;

    NSURLComponents *c = [[NSURLComponents alloc] init];
    c.scheme = MMProtocolScheme(self.proto);
    c.host = self.host;
    if (self.port > 0) c.port = @(self.port);

    // O setter de -path faz o percent-encoding; guardamos o caminho decodificado
    // justamente para não escapar duas vezes o que o usuário colou já escapado.
    NSString *p = [self normalizedSharePath];
    c.path = p.length > 0 ? [@"/" stringByAppendingString:p] : @"/";

    return c.URL;
}

- (NSString *)displayName {
    if (self.name.length > 0) return self.name;
    NSString *p = [self normalizedSharePath];
    if (self.host.length == 0) return NSLocalizedString(@"share.untitled", @"Novo compartilhamento");
    return p.length > 0 ? [NSString stringWithFormat:@"%@/%@", self.host, p] : self.host;
}

- (nullable NSString *)validationError {
    if (self.host.length == 0) {
        return NSLocalizedString(@"validate.noHost", @"Informe o servidor.");
    }
    if ([self.host rangeOfString:@"/"].location != NSNotFound) {
        return NSLocalizedString(@"validate.badHost", @"O servidor não pode conter barras.");
    }
    if (self.port < 0 || self.port > 65535) {
        return NSLocalizedString(@"validate.badPort", @"Porta inválida.");
    }
    // NFS monta um caminho exportado; sem ele não há o que montar.
    if (self.proto == MMProtocolNFS && [self normalizedSharePath].length == 0) {
        return NSLocalizedString(@"validate.noExport", @"Informe o caminho exportado.");
    }
    if ([self mountURL] == nil) {
        return NSLocalizedString(@"validate.badURL", @"Não foi possível montar um endereço válido.");
    }
    return nil;
}

#pragma mark - Parsing da entrada do usuário

/// Separa "host", "host:445", "[::1]", "[::1]:445" em host e porta.
static void MMSplitHostPort(NSString *hostPort, NSString **outHost, NSInteger *outPort) {
    NSString *host = hostPort;
    NSInteger port = 0;

    if ([hostPort hasPrefix:@"["]) {
        NSRange close = [hostPort rangeOfString:@"]"];
        if (close.location != NSNotFound) {
            host = [hostPort substringWithRange:NSMakeRange(1, close.location - 1)];
            NSString *rest = [hostPort substringFromIndex:NSMaxRange(close)];
            if ([rest hasPrefix:@":"]) port = [[rest substringFromIndex:1] integerValue];
        }
    } else {
        NSRange colon = [hostPort rangeOfString:@":" options:NSBackwardsSearch];
        if (colon.location != NSNotFound) {
            NSString *head = [hostPort substringToIndex:colon.location];
            NSString *tail = [hostPort substringFromIndex:NSMaxRange(colon)];
            NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];

            // "servidor:" (típico de NFS, "servidor:/export") não traz porta, e
            // vários ":" significam IPv6 sem colchetes — nos dois casos o host
            // é a string inteira.
            BOOL isPort = tail.length > 0
                && [tail rangeOfCharacterFromSet:nonDigits].location == NSNotFound
                && [head rangeOfString:@":"].location == NSNotFound;
            if (isPort) {
                host = head;
                port = [tail integerValue];
            } else if (tail.length == 0 && [head rangeOfString:@":"].location == NSNotFound) {
                host = head;  // "servidor:" -> "servidor"
            }
        }
    }

    if (outHost) *outHost = host;
    if (outPort) *outPort = port;
}

+ (instancetype)shareWithUserInput:(NSString *)text {
    MMShare *share = [[MMShare alloc] init];

    NSString *s = [(text ?: @"") stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (s.length == 0) return share;

    // UNC do Windows (\\SERVIDOR\Publico) vira o mesmo formato de "//host/share".
    s = [s stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];

    NSString *rest = s;
    NSRange schemeSep = [s rangeOfString:@"://"];
    if (schemeSep.location != NSNotFound) {
        NSString *scheme = [s substringToIndex:schemeSep.location];
        MMProtocol p;
        if (MMProtocolFromScheme(scheme, &p)) share.proto = p;
        rest = [s substringFromIndex:NSMaxRange(schemeSep)];
    } else {
        while ([rest hasPrefix:@"/"]) rest = [rest substringFromIndex:1];
    }

    // Separa o "usuario@" que precede o host — o "@" válido é o último antes da
    // primeira barra, para não confundir com "@" dentro do caminho.
    NSRange firstSlash = [rest rangeOfString:@"/"];
    NSUInteger hostEnd = (firstSlash.location == NSNotFound) ? rest.length : firstSlash.location;
    NSString *authority = [rest substringToIndex:hostEnd];
    NSString *pathPart = (firstSlash.location == NSNotFound)
        ? @"" : [rest substringFromIndex:NSMaxRange(firstSlash)];

    NSRange at = [authority rangeOfString:@"@" options:NSBackwardsSearch];
    if (at.location != NSNotFound) {
        NSString *user = [authority substringToIndex:at.location];
        if (user.length > 0) {
            share.username = [user stringByRemovingPercentEncoding] ?: user;
        }
        authority = [authority substringFromIndex:NSMaxRange(at)];
    }

    NSString *host = nil;
    NSInteger port = 0;
    MMSplitHostPort(authority, &host, &port);
    share.host = [host stringByRemovingPercentEncoding] ?: host;
    share.port = port;

    // Guardamos o caminho decodificado; -mountURL reencoda na hora de montar.
    share.sharePath = [pathPart stringByRemovingPercentEncoding] ?: pathPart;
    share.sharePath = [share normalizedSharePath];

    NSArray<NSString *> *comps = [share.sharePath componentsSeparatedByString:@"/"];
    share.name = comps.lastObject.length > 0 ? comps.lastObject : share.host;

    return share;
}

#pragma mark - Persistência

+ (nullable instancetype)shareWithJSONObject:(NSDictionary *)obj {
    if (![obj isKindOfClass:[NSDictionary class]]) return nil;

    NSString *host = obj[@"host"];
    if (![host isKindOfClass:[NSString class]] || host.length == 0) return nil;

    MMShare *s = [[MMShare alloc] init];
    if ([obj[@"id"] isKindOfClass:[NSString class]]) s.identifier = obj[@"id"];
    if ([obj[@"name"] isKindOfClass:[NSString class]]) s.name = obj[@"name"];
    s.host = host;

    MMProtocol p = MMProtocolSMB;
    if ([obj[@"scheme"] isKindOfClass:[NSString class]]) MMProtocolFromScheme(obj[@"scheme"], &p);
    s.proto = p;

    if ([obj[@"port"] isKindOfClass:[NSNumber class]]) s.port = [obj[@"port"] integerValue];
    if ([obj[@"share"] isKindOfClass:[NSString class]]) s.sharePath = obj[@"share"];
    if ([obj[@"user"] isKindOfClass:[NSString class]]) s.username = obj[@"user"];

    s.guest         = [obj[@"guest"] boolValue];
    s.readOnly      = [obj[@"readOnly"] boolValue];
    s.hideOnDesktop = [obj[@"hideOnDesktop"] boolValue];
    s.mountAtLogin  = [obj[@"mountAtLogin"] boolValue];
    // Ausente em cofres antigos significa "sim" — é o padrão do app.
    s.savePassword  = obj[@"savePassword"] ? [obj[@"savePassword"] boolValue] : YES;

    return s;
}

- (NSDictionary *)JSONObject {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"id"]            = self.identifier;
    d[@"name"]          = self.name ?: @"";
    d[@"scheme"]        = MMProtocolScheme(self.proto);
    d[@"host"]          = self.host ?: @"";
    d[@"share"]         = [self normalizedSharePath];
    if (self.port > 0) d[@"port"] = @(self.port);
    if (self.username.length > 0) d[@"user"] = self.username;
    d[@"guest"]         = @(self.guest);
    d[@"readOnly"]      = @(self.readOnly);
    d[@"hideOnDesktop"] = @(self.hideOnDesktop);
    d[@"mountAtLogin"]  = @(self.mountAtLogin);
    d[@"savePassword"]  = @(self.savePassword);
    return d;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<MMShare %@ %@>",
            self.displayName, [self mountURL].absoluteString ?: @"(sem URL)"];
}

@end
