
all: build test

prep: npm-install

npm-install:
	npm install

build: lex-parser.js

lex-parser.js: lex.y lex.l
	@[ -a  ./node_modules/.bin/jison ] || echo "### FAILURE: Make sure you have run 'make prep' before as the jison compiler is unavailable! ###"
	sh node_modules/.bin/jison -o lex-parser.js lex.y lex.l

test:
	node tests/all-tests.js




clean:
	-rm -f lex-parser.js
	-rm -rf node_modules/

superclean: clean
	-find . -type d -name 'node_modules' -exec rm -rf "{}" \;





.PHONY: all prep npm-install build test clean superclean
