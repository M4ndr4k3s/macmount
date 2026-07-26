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
        case MMProtocolEFI:      return @"efi";
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
        case MMProtocolEFI:      return NSLocalizedString(@"proto.efi", @"Disco Local / EFI");
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
    } else if ([s isEqualToString:@"efi"]) {
        p = MMProtocolEFI;
    } else {
        return NO;
    }
    if (outProto) *outProto = p;
    return YES;
}

NSArray<NSNumber *> *MMAllProtocols(void) {
    return @[ @(MMProtocolSMB), @(MMProtocolAFP), @(MMProtocolNFS),
              @(MMProtocolWebDAV), @(MMProtocolWebDAVS), @(MMProtocolEFI) ];
}

NSArray<NSString *> *MMShareFieldNames(void) {
    return @[ @"identifier", @"name", @"proto", @"host", @"port", @"sharePath",
              @"username", @"diskIdentifier", @"guest", @"readOnly", @"hideOnDesktop",
              @"mountAtLogin", @"savePassword", @"reconnect" ];
}

#pragma mark - Funções puras de host e caminho

void MMSplitHostPort(NSString *hostPort,
                     NSString *_Nullable *_Nullable outHost,
                     NSInteger *_Nullable outPort) {
    NSString *host = hostPort ?: @"";
    NSInteger port = 0;

    if ([host hasPrefix:@"["]) {
        NSRange close = [host rangeOfString:@"]"];
        if (close.location != NSNotFound) {
            NSString *rest = [host substringFromIndex:NSMaxRange(close)];
            host = [host substringWithRange:NSMakeRange(1, close.location - 1)];
            if ([rest hasPrefix:@":"]) port = [[rest substringFromIndex:1] integerValue];
        }
    } else {
        NSRange colon = [host rangeOfString:@":" options:NSBackwardsSearch];
        if (colon.location != NSNotFound) {
            NSString *head = [host substringToIndex:colon.location];
            NSString *tail = [host substringFromIndex:NSMaxRange(colon)];
            NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];

            // Um ":" sobrando em `head` significa IPv6 sem colchetes: aí a
            // string inteira é o host, porque não há porta nenhuma ali.
            BOOL headIsPlainHost = ([head rangeOfString:@":"].location == NSNotFound);
            BOOL tailIsNumber = tail.length > 0
                && [tail rangeOfCharacterFromSet:nonDigits].location == NSNotFound;

            if (headIsPlainHost && tailIsNumber) {
                host = head;
                port = [tail integerValue];
            } else if (headIsPlainHost && tail.length == 0) {
                host = head;  // "servidor:" -> "servidor"
            }
        }
    }

    if (outHost) *outHost = host;
    if (outPort) *outPort = port;
}

NSString *MMJoinPathComponents(NSString *_Nullable path) {
    NSString *p = [(path ?: @"") stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *component in [p componentsSeparatedByString:@"/"]) {
        NSString *trimmed = [component stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length > 0) [parts addObject:trimmed];
    }
    return [parts componentsJoinedByString:@"/"];
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

/// Copiar campo a campo à mão convida ao esquecimento silencioso: um campo novo
/// que ficasse de fora se perderia toda vez que a folha de edição chamasse -copy,
/// sem erro nenhum para observar. Percorrer MMShareFieldNames() troca isso por
/// uma lista que os testes conferem contra as @property declaradas.
- (id)copyWithZone:(NSZone *)zone {
    MMShare *c = [[MMShare allocWithZone:zone] init];
    for (NSString *field in MMShareFieldNames()) {
        [c setValue:[self valueForKey:field] forKey:field];
    }
    return c;
}

#pragma mark - Caminho e URL

- (NSString *)normalizedSharePath {
    return MMJoinPathComponents(self.sharePath);
}

- (nullable NSURL *)mountURL {
    // EFI monta via diskutil; não usa URL.
    if (self.proto == MMProtocolEFI) return nil;

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
    if (self.proto == MMProtocolEFI) {
        if (self.diskIdentifier.length > 0) {
            return [NSString stringWithFormat:@"EFI (%@)", self.diskIdentifier];
        }
        return NSLocalizedString(@"share.untitled", @"Novo compartilhamento");
    }
    NSString *p = [self normalizedSharePath];
    if (self.host.length == 0) return NSLocalizedString(@"share.untitled", @"Novo compartilhamento");
    return p.length > 0 ? [NSString stringWithFormat:@"%@/%@", self.host, p] : self.host;
}

- (nullable NSString *)validationError {
    if (self.proto == MMProtocolEFI) {
        if (self.diskIdentifier.length == 0) {
            return NSLocalizedString(@"validate.noDisk", @"Informe o identificador do disco (ex.: disk0s1).");
        }
        return nil;
    }
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

    MMShare *s = [[MMShare alloc] init];
    if ([obj[@"id"] isKindOfClass:[NSString class]]) s.identifier = obj[@"id"];
    if ([obj[@"name"] isKindOfClass:[NSString class]]) s.name = obj[@"name"];

    MMProtocol p = MMProtocolSMB;
    if ([obj[@"scheme"] isKindOfClass:[NSString class]]) MMProtocolFromScheme(obj[@"scheme"], &p);
    s.proto = p;

    if (p == MMProtocolEFI) {
        if ([obj[@"diskId"] isKindOfClass:[NSString class]]) s.diskIdentifier = obj[@"diskId"];
        // EFI não precisa de host; pode retornar válido sem ele.
    } else {
        NSString *host = obj[@"host"];
        if (![host isKindOfClass:[NSString class]] || host.length == 0) return nil;
        s.host = host;
        if ([obj[@"port"] isKindOfClass:[NSNumber class]]) s.port = [obj[@"port"] integerValue];
        if ([obj[@"share"] isKindOfClass:[NSString class]]) s.sharePath = obj[@"share"];
        if ([obj[@"user"] isKindOfClass:[NSString class]]) s.username = obj[@"user"];
        s.guest         = [obj[@"guest"] boolValue];
        s.savePassword  = obj[@"savePassword"] ? [obj[@"savePassword"] boolValue] : YES;
    }

    s.readOnly      = [obj[@"readOnly"] boolValue];
    s.hideOnDesktop = [obj[@"hideOnDesktop"] boolValue];
    s.mountAtLogin  = [obj[@"mountAtLogin"] boolValue];
    s.reconnect     = [obj[@"reconnect"] boolValue];

    return s;
}

- (NSDictionary *)JSONObject {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"id"]            = self.identifier;
    d[@"name"]          = self.name ?: @"";
    d[@"scheme"]        = MMProtocolScheme(self.proto);

    if (self.proto == MMProtocolEFI) {
        if (self.diskIdentifier.length > 0) d[@"diskId"] = self.diskIdentifier;
    } else {
        d[@"host"]          = self.host ?: @"";
        d[@"share"]         = [self normalizedSharePath];
        if (self.port > 0) d[@"port"] = @(self.port);
        if (self.username.length > 0) d[@"user"] = self.username;
        d[@"guest"]         = @(self.guest);
        d[@"savePassword"]  = @(self.savePassword);
    }

    d[@"readOnly"]      = @(self.readOnly);
    d[@"hideOnDesktop"] = @(self.hideOnDesktop);
    d[@"mountAtLogin"]  = @(self.mountAtLogin);
    d[@"reconnect"]     = @(self.reconnect);
    return d;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<MMShare %@ %@>",
            self.displayName, [self mountURL].absoluteString ?: @"(sem URL)"];
}

@end
