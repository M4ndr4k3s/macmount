//
//  MMEditSheet.m
//

#import "MMEditSheet.h"

#import "MMBrowser.h"
#import "MMKeychain.h"
#import "MMStore.h"

@interface MMEditSheet () <MMBrowserDelegate, NSComboBoxDelegate>

@property (nonatomic, strong) NSWindow *sheet;
@property (nonatomic, strong) NSWindow *parent;
@property (nonatomic, strong) MMShare *share;
@property (nonatomic, assign) BOOL isNew;
@property (nonatomic, copy) void (^completion)(MMShare *_Nullable);
@property (nonatomic, strong) MMBrowser *browser;
@property (nonatomic, strong) MMEditSheet *selfRetain;

@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSPopUpButton *protocolPopUp;
@property (nonatomic, strong) NSComboBox *hostField;
@property (nonatomic, strong) NSTextField *shareField;
@property (nonatomic, strong) NSTextField *userField;
@property (nonatomic, strong) NSSecureTextField *passwordField;

@property (nonatomic, strong) NSButton *guestCheck;
@property (nonatomic, strong) NSButton *savePasswordCheck;
@property (nonatomic, strong) NSButton *readOnlyCheck;
@property (nonatomic, strong) NSButton *hideCheck;
@property (nonatomic, strong) NSButton *loginCheck;
@property (nonatomic, strong) NSButton *reconnectCheck;

@end

@implementation MMEditSheet

+ (void)presentForShare:(nullable MMShare *)share
               inWindow:(NSWindow *)parent
             completion:(void (^)(MMShare *_Nullable))completion {
    MMEditSheet *controller = [[MMEditSheet alloc] init];
    controller.isNew = (share == nil);
    controller.share = share ? [share copy] : [[MMShare alloc] init];
    controller.parent = parent;
    controller.completion = completion;
    controller.selfRetain = controller;
    [controller present];
}

#pragma mark - Construção

- (void)present {
    [self buildSheet];
    [self loadFromShare];

    self.browser = [[MMBrowser alloc] init];
    self.browser.delegate = self;
    [self.browser start];

    [self.parent beginSheet:self.sheet completionHandler:nil];
    [self.sheet makeFirstResponder:(self.isNew ? self.hostField : self.nameField)];
}

- (NSTextField *)label:(NSString *)text {
    NSTextField *field = [NSTextField labelWithString:text];
    field.alignment = NSTextAlignmentRight;
    return field;
}

- (NSButton *)checkbox:(NSString *)title {
    NSButton *button = [NSButton checkboxWithTitle:title target:self action:@selector(checkboxChanged:)];
    return button;
}

- (void)buildSheet {
    self.nameField = [NSTextField textFieldWithString:@""];
    self.nameField.placeholderString = NSLocalizedString(@"edit.namePlaceholder", @"Opcional");

    self.protocolPopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSNumber *proto in MMAllProtocols()) {
        [self.protocolPopUp addItemWithTitle:MMProtocolDisplayName((MMProtocol)proto.integerValue)];
        self.protocolPopUp.lastItem.tag = proto.integerValue;
    }
    self.protocolPopUp.target = self;
    self.protocolPopUp.action = @selector(protocolChanged:);

    self.hostField = [[NSComboBox alloc] initWithFrame:NSZeroRect];
    self.hostField.completes = YES;
    self.hostField.usesDataSource = NO;
    self.hostField.delegate = self;
    self.hostField.placeholderString =
        NSLocalizedString(@"edit.hostPlaceholder", @"servidor.local, 192.168.0.10 ou \\\\SERVIDOR\\Publico");

    self.shareField = [NSTextField textFieldWithString:@""];
    self.shareField.placeholderString = NSLocalizedString(@"edit.sharePlaceholder", @"Publico");

    self.userField = [NSTextField textFieldWithString:@""];
    self.userField.placeholderString = NSLocalizedString(@"edit.userPlaceholder", @"Deixe vazio para perguntar");
    // "Guardar no Keychain" só faz sentido com usuário preenchido, e isso muda
    // enquanto se digita — sem o delegate a caixa ficaria travada.
    self.userField.delegate = self;

    self.passwordField = [[NSSecureTextField alloc] initWithFrame:NSZeroRect];

    self.guestCheck = [self checkbox:NSLocalizedString(@"edit.guest", @"Conectar como convidado")];
    self.savePasswordCheck = [self checkbox:NSLocalizedString(@"edit.savePassword", @"Guardar a senha no Keychain")];
    self.readOnlyCheck = [self checkbox:NSLocalizedString(@"edit.readOnly", @"Montar somente leitura")];
    self.hideCheck = [self checkbox:NSLocalizedString(@"edit.hide", @"Não mostrar na mesa")];
    self.loginCheck = [self checkbox:NSLocalizedString(@"edit.mountAtLogin", @"Montar ao iniciar a sessão")];
    self.reconnectCheck = [self checkbox:NSLocalizedString(@"edit.reconnect", @"Reconectar quando a rede voltar")];

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[ [self label:NSLocalizedString(@"edit.name", @"Nome:")],       self.nameField ],
        @[ [self label:NSLocalizedString(@"edit.protocol", @"Protocolo:")], self.protocolPopUp ],
        @[ [self label:NSLocalizedString(@"edit.host", @"Servidor:")],   self.hostField ],
        @[ [self label:NSLocalizedString(@"edit.share", @"Compartilhamento:")], self.shareField ],
        @[ [self label:NSLocalizedString(@"edit.user", @"Usuário:")],    self.userField ],
        @[ [self label:NSLocalizedString(@"edit.password", @"Senha:")],  self.passwordField ],
        @[ [NSGridCell emptyContentView], self.guestCheck ],
        @[ [NSGridCell emptyContentView], self.savePasswordCheck ],
        @[ [NSGridCell emptyContentView], self.readOnlyCheck ],
        @[ [NSGridCell emptyContentView], self.hideCheck ],
        @[ [NSGridCell emptyContentView], self.loginCheck ],
        @[ [NSGridCell emptyContentView], self.reconnectCheck ],
    ]];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    grid.rowSpacing = 8.0;
    grid.columnSpacing = 10.0;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid columnAtIndex:1].xPlacement = NSGridCellPlacementFill;
    for (NSInteger i = 0; i < grid.numberOfRows; i++) {
        [grid rowAtIndex:i].yPlacement = NSGridCellPlacementCenter;
    }
    // Um respiro antes do bloco de opções.
    [grid rowAtIndex:6].topPadding = 8.0;

    NSButton *cancel = [NSButton buttonWithTitle:NSLocalizedString(@"alert.cancel", @"Cancelar")
                                          target:self action:@selector(cancel:)];
    cancel.keyEquivalent = @"\033";
    cancel.translatesAutoresizingMaskIntoConstraints = NO;

    NSButton *save = [NSButton buttonWithTitle:NSLocalizedString(@"edit.save", @"Salvar")
                                        target:self action:@selector(save:)];
    save.keyEquivalent = @"\r";
    save.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 400)];
    [content addSubview:grid];
    [content addSubview:cancel];
    [content addSubview:save];

    [NSLayoutConstraint activateConstraints:@[
        [grid.topAnchor constraintEqualToAnchor:content.topAnchor constant:20],
        [grid.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [grid.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],

        [save.topAnchor constraintEqualToAnchor:grid.bottomAnchor constant:20],
        [save.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [save.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-20],
        [save.widthAnchor constraintGreaterThanOrEqualToConstant:90],

        [cancel.centerYAnchor constraintEqualToAnchor:save.centerYAnchor],
        [cancel.trailingAnchor constraintEqualToAnchor:save.leadingAnchor constant:-12],
        [cancel.widthAnchor constraintGreaterThanOrEqualToConstant:90],

        [content.widthAnchor constraintGreaterThanOrEqualToConstant:480],
    ]];

    self.sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 480, 400)
                                             styleMask:NSWindowStyleMaskTitled
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    self.sheet.contentView = content;

    // A altura vem do conteúdo, não de um número escrito à mão: acrescentar uma
    // linha ao formulário não pode espremer o resto nem cortar os botões.
    NSSize fitting = [content fittingSize];
    [self.sheet setContentSize:NSMakeSize(MAX(480.0, fitting.width), fitting.height)];
}

#pragma mark - Campos <-> modelo

- (void)loadFromShare {
    MMShare *s = self.share;
    self.nameField.stringValue = s.name ?: @"";
    self.hostField.stringValue = s.host ?: @"";
    self.shareField.stringValue = [s normalizedSharePath];
    self.userField.stringValue = s.username ?: @"";

    [self.protocolPopUp selectItemWithTag:s.proto];

    self.guestCheck.state        = s.guest ? NSControlStateValueOn : NSControlStateValueOff;
    self.savePasswordCheck.state = s.savePassword ? NSControlStateValueOn : NSControlStateValueOff;
    self.readOnlyCheck.state     = s.readOnly ? NSControlStateValueOn : NSControlStateValueOff;
    self.hideCheck.state         = s.hideOnDesktop ? NSControlStateValueOn : NSControlStateValueOff;
    self.loginCheck.state        = s.mountAtLogin ? NSControlStateValueOn : NSControlStateValueOff;
    self.reconnectCheck.state    = s.reconnect ? NSControlStateValueOn : NSControlStateValueOff;

    if (!self.isNew) {
        NSString *existing = [MMKeychain passwordForShare:s];
        if (existing.length > 0) self.passwordField.stringValue = existing;
    }

    [self updateEnabledStates];
}

- (MMShare *)shareFromFields {
    MMShare *s = [self.share copy];
    s.name      = [self.nameField.stringValue stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceCharacterSet]];
    s.proto     = (MMProtocol)self.protocolPopUp.selectedTag;
    s.sharePath = self.shareField.stringValue;
    s.username  = [self.userField.stringValue stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceCharacterSet]];

    // O host pode ter porta colada junto ("servidor:445"); reaproveitamos o
    // parser para não duplicar essa regra aqui.
    MMShare *parsedHost = [MMShare shareWithUserInput:self.hostField.stringValue];
    s.host = parsedHost.host;
    s.port = parsedHost.port;

    s.guest         = (self.guestCheck.state == NSControlStateValueOn);
    s.savePassword  = (self.savePasswordCheck.state == NSControlStateValueOn);
    s.readOnly      = (self.readOnlyCheck.state == NSControlStateValueOn);
    s.hideOnDesktop = (self.hideCheck.state == NSControlStateValueOn);
    s.mountAtLogin  = (self.loginCheck.state == NSControlStateValueOn);
    s.reconnect     = (self.reconnectCheck.state == NSControlStateValueOn);
    return s;
}

- (void)updateEnabledStates {
    BOOL guest = (self.guestCheck.state == NSControlStateValueOn);
    MMProtocol proto = (MMProtocol)self.protocolPopUp.selectedTag;
    BOOL supportsAuth = (proto != MMProtocolNFS);

    self.userField.enabled = !guest && supportsAuth;
    self.passwordField.enabled = !guest && supportsAuth;
    self.savePasswordCheck.enabled = !guest && supportsAuth && self.userField.stringValue.length > 0;
    self.guestCheck.enabled = supportsAuth;
}

#pragma mark - Ações

- (void)checkboxChanged:(id)sender {
    [self updateEnabledStates];
}

- (void)protocolChanged:(id)sender {
    [self updateEnabledStates];
}

- (void)controlTextDidChange:(NSNotification *)note {
    if (note.object == self.userField) [self updateEnabledStates];
}

/// Quando o usuário cola um caminho inteiro no campo de servidor
/// (\\SERVIDOR\Publico, smb://...), distribuímos entre os campos certos.
- (void)controlTextDidEndEditing:(NSNotification *)note {
    if (note.object != self.hostField) return;

    NSString *text = self.hostField.stringValue;
    BOOL looksLikePath = [text containsString:@"\\"] || [text containsString:@"://"]
                      || [text containsString:@"/"];
    if (!looksLikePath) return;

    MMShare *parsed = [MMShare shareWithUserInput:text];
    if (parsed.host.length == 0) return;

    self.hostField.stringValue = parsed.host;
    if (parsed.sharePath.length > 0) self.shareField.stringValue = parsed.sharePath;
    if (parsed.username.length > 0 && self.userField.stringValue.length == 0) {
        self.userField.stringValue = parsed.username;
    }
    if (self.nameField.stringValue.length == 0 && parsed.name.length > 0) {
        self.nameField.stringValue = parsed.name;
    }
    [self.protocolPopUp selectItemWithTag:parsed.proto];
    [self updateEnabledStates];
}

- (void)cancel:(id)sender {
    [self dismissWithResult:nil];
}

- (void)save:(id)sender {
    MMShare *candidate = [self shareFromFields];

    NSString *problem = [candidate validationError];
    if (problem != nil) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSAlertStyleWarning;
        alert.messageText = NSLocalizedString(@"edit.invalid", @"Entrada incompleta");
        alert.informativeText = problem;
        [alert addButtonWithTitle:NSLocalizedString(@"alert.ok", @"OK")];
        [alert beginSheetModalForWindow:self.sheet completionHandler:nil];
        return;
    }

    NSString *password = self.passwordField.stringValue;
    if (candidate.savePassword && [MMKeychain canStorePasswordForShare:candidate]) {
        NSError *keychainError = nil;
        if (![MMKeychain setPassword:password forShare:candidate error:&keychainError]
            && password.length > 0) {
            NSLog(@"[MacMount] não foi possível guardar a senha: %@",
                  keychainError.localizedDescription);
        }
    } else if (!candidate.savePassword) {
        [MMKeychain removePasswordForShare:candidate];
    }

    if (self.isNew) {
        [[MMStore shared] addShare:candidate];
    } else {
        [[MMStore shared] updateShare:candidate];
    }

    [self dismissWithResult:candidate];
}

- (void)dismissWithResult:(nullable MMShare *)result {
    [self.browser stop];
    self.browser.delegate = nil;

    [self.parent endSheet:self.sheet];
    [self.sheet orderOut:nil];

    if (self.completion) self.completion(result);

    self.completion = nil;
    self.selfRetain = nil;
}

#pragma mark - MMBrowserDelegate

- (void)browserDidUpdateServers:(NSArray<MMDiscoveredServer *> *)servers {
    NSString *typed = self.hostField.stringValue;

    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (MMDiscoveredServer *server in servers) {
        NSString *value = server.hostname.length > 0 ? server.hostname : server.displayName;
        if (![names containsObject:value]) [names addObject:value];
    }

    [self.hostField removeAllItems];
    [self.hostField addItemsWithObjectValues:names];
    self.hostField.stringValue = typed;  // a lista não pode roubar o que já foi digitado
}

@end
