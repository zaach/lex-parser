
all: build test

prep: npm-install

npm-install:
	npm install

build: lex-parser.js

lex-parser.js: lex.y lex.l
	./node_modules/.bin/jison -o lex-parser.js lex.y lex.l

test:
	node tests/all-tests.js




clean:
	-rm -f lex-parser.js
	-rm -rf node_modules/

superclean: clean
	-find . -type d -name 'node_modules' -exec rm -rf "{}" \;





.PHONY: all prep npm-install build test clean superclean
