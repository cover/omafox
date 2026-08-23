PREFIX ?= /usr
DESTDIR ?=
BUILD_DIR ?= build
CC ?= cc

NATIVE_HOST := $(BUILD_DIR)/omafox-native-host
NATIVE_SOURCE := omarchy/omafox-native-host.c

CFLAGS += -std=c17 -Wall -Wextra -Wpedantic

.PHONY: all clean install

all: $(NATIVE_HOST)

$(NATIVE_HOST): $(NATIVE_SOURCE) | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $< $(LDFLAGS)

$(BUILD_DIR):
	mkdir -p $@

install: all
	install -Dm755 omarchy/omafox "$(DESTDIR)$(PREFIX)/bin/omafox"
	install -Dm755 $(NATIVE_HOST) "$(DESTDIR)$(PREFIX)/lib/omafox/omafox-native-host"
	install -Dm644 packaging/org.omarchy.omafox.json "$(DESTDIR)$(PREFIX)/lib/mozilla/native-messaging-hosts/org.omarchy.omafox.json"
	install -Dm755 packaging/omafox-hook "$(DESTDIR)$(PREFIX)/share/omafox/hooks/omafox"
	install -Dm644 README.md "$(DESTDIR)$(PREFIX)/share/doc/omafox/README.md"
	install -Dm644 LICENSE "$(DESTDIR)$(PREFIX)/share/licenses/omafox/LICENSE"

clean:
	rm -rf "$(BUILD_DIR)"
