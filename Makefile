
all: npm-install build test

npm-install:
	npm install

build: lex-parser.js

lex-parser.js: lex.y lex.l
	./node_modules/.bin/jison -o lex-parser.js lex.y lex.l

test:
	node tests/all-tests.js




clean:
	-rm -f lex-parser.js

superclean: clean
	-find . -type d -name 'node_modules' -exec rm -rf "{}" \;





.PHONY: all npm-install build test clean superclean
