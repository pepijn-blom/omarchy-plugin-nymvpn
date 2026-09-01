.PHONY: all install uninstall test validate

all: test

install:
	@./install

uninstall:
	@./uninstall

test:
	@python3 -m unittest tests.test_status tests.test_login tests.test_split
	@node tests/test_model.js

validate: test
	@omarchy plugin validate .
