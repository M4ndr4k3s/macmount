//
//  MMMainMenu.m
//

#import "MMMainMenu.h"

@implementation MMMainMenu

/// Todo menu do topo é a mesma cerimônia: criar o NSMenu, embrulhar num
/// NSMenuItem sem título e pendurar no menu principal. Só isso é comum aos três
/// — os itens continuam escritos um a um, com @selector de verdade, porque
/// selector em string não é conferido por nada e não aparece numa busca.
+ (NSMenu *)addSubmenuNamed:(NSString *)title to:(NSMenu *)mainMenu {
    NSMenu *submenu = [[NSMenu alloc] initWithTitle:title];
    NSMenuItem *item = [[NSMenuItem alloc] init];
    item.submenu = submenu;
    [mainMenu addItem:item];
    return submenu;
}

+ (void)install {
    NSString *appName = NSLocalizedString(@"app.name", @"MacMount");
    NSMenu *mainMenu = [[NSMenu alloc] init];

    NSMenu *appMenu = [self addSubmenuNamed:appName to:mainMenu];
    [appMenu addItemWithTitle:[NSString stringWithFormat:
                               NSLocalizedString(@"menu.aboutFmt", @"Sobre o %@"), appName]
                       action:@selector(orderFrontStandardAboutPanel:)
                keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:NSLocalizedString(@"menu.add", @"Adicionar compartilhamento…")
                       action:@selector(addShare:)
                keyEquivalent:@"n"];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:[NSString stringWithFormat:
                               NSLocalizedString(@"menu.hideFmt", @"Ocultar %@"), appName]
                       action:@selector(hide:)
                keyEquivalent:@"h"];
    [appMenu addItemWithTitle:[NSString stringWithFormat:
                               NSLocalizedString(@"menu.quitFmt", @"Sair do %@"), appName]
                       action:@selector(terminate:)
                keyEquivalent:@"q"];

    NSMenu *editMenu = [self addSubmenuNamed:NSLocalizedString(@"menu.edit", @"Editar")
                                          to:mainMenu];
    [editMenu addItemWithTitle:NSLocalizedString(@"menu.cut", @"Recortar")
                        action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:NSLocalizedString(@"menu.copy", @"Copiar")
                        action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:NSLocalizedString(@"menu.paste", @"Colar")
                        action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:NSLocalizedString(@"menu.selectAll", @"Selecionar tudo")
                        action:@selector(selectAll:) keyEquivalent:@"a"];

    NSMenu *windowMenu = [self addSubmenuNamed:NSLocalizedString(@"menu.window", @"Janela")
                                            to:mainMenu];
    [windowMenu addItemWithTitle:NSLocalizedString(@"menu.minimize", @"Minimizar")
                          action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:NSLocalizedString(@"menu.close", @"Fechar")
                          action:@selector(performClose:) keyEquivalent:@"w"];

    NSApp.mainMenu = mainMenu;
    NSApp.windowsMenu = windowMenu;
}

@end
