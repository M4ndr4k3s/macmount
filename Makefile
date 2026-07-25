# MacMount — build sem projeto Xcode.
#
#   make          compila MacMount.app universal
#   make check    build + verificações estáticas (piso 10.13, arquiteturas, i18n)
#   make test     testes de lógica
#   make smoke    constrói a interface fora da tela e sai
#   make dist     dmg + zip para distribuição
#   make clean

BUILD   ?= build
VERSION := $(shell tr -d ' \n' < VERSION)
APP      = $(BUILD)/MacMount.app
BIN      = $(APP)/Contents/MacOS/MacMount

# Os mesmos avisos-como-erro do app, porque os testes compilam o código de
# produção. Sem -mmacosx-version-min de propósito: o binário de teste precisa
# rodar na máquina atual, e num runner arm64 pedir piso 10.13 não é válido
# (arm64 começa no 11.0). A garantia de compatibilidade com o 10.13 vem da
# compilação real em scripts/build-app.sh, que passa pelos mesmos arquivos.
TEST_FLAGS = -fobjc-arc -O1 -Wall -Wextra -Wno-unused-parameter \
             -Werror=unguarded-availability -Werror=unguarded-availability-new \
             -Werror=objc-method-access -Werror=incompatible-pointer-types \
             -Isrc

TEST_SOURCES = src/MMShare.m src/MMMounter.m test/logic_tests.m

.PHONY: all check test smoke strings dist clean icon mount-smoke

all:
	@scripts/build-app.sh $(BUILD)

check: all strings
	@scripts/check-bundle.sh $(BUILD)

strings:
	@python3 scripts/check-strings.py .

test:
	@mkdir -p $(BUILD)
	@clang $(TEST_FLAGS) $(TEST_SOURCES) \
	    -framework Cocoa -framework NetFS -o $(BUILD)/logic_tests
	@$(BUILD)/logic_tests

smoke: all
	@$(BIN) --smoke

# Monta um servidor SMB de verdade. Precisa de um servidor: no CI é um Samba
# local, na sua máquina pode ser o NAS ou o Windows da rede.
#   make mount-smoke ARGS="smb://SERVIDOR/Publico leandro senha"
mount-smoke:
	@mkdir -p $(BUILD)
	@clang $(TEST_FLAGS) src/MMShare.m src/MMMounter.m test/mount_smoke.m \
	    -framework Cocoa -framework NetFS -o $(BUILD)/mount_smoke
	@$(BUILD)/mount_smoke $(ARGS)

# Imagem de disco com atalho para /Applications, como manda o costume no Mac.
dist: check
	@rm -rf $(BUILD)/dmg $(BUILD)/*.dmg $(BUILD)/*.zip
	@mkdir -p $(BUILD)/dmg
	@cp -R $(APP) $(BUILD)/dmg/
	@ln -s /Applications $(BUILD)/dmg/Applications
	@hdiutil create -volname "MacMount $(VERSION)" -srcfolder $(BUILD)/dmg \
	    -ov -quiet -format UDZO $(BUILD)/MacMount-$(VERSION)-universal.dmg
	@ditto -c -k --keepParent $(APP) $(BUILD)/MacMount-$(VERSION)-universal.zip
	@rm -rf $(BUILD)/dmg
	@echo "==> $(BUILD)/MacMount-$(VERSION)-universal.dmg"
	@echo "==> $(BUILD)/MacMount-$(VERSION)-universal.zip"

# Regera o PNG do ícone a partir do script (roda em qualquer sistema).
icon:
	@python3 scripts/gen-icon.py resources/icon.png

clean:
	@rm -rf $(BUILD)
