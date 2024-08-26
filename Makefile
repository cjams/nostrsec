#
# Makefile for generating python-based nostr parser using antlr4
#

ANTLR_BINARY := antlr4
GRAMMAR := nostr.g4
OUTPUT := output

all: antlr4

antlr4: $(GRAMMAR)
	mkdir -p $(OUTPUT)
	$(ANTLR_BINARY) -Dlanguage=Python3 -o $(OUTPUT) $<

clean:
	rm -rf $(OUTPUT) 

.PHONY: all antlr4 clean
