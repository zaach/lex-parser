
ifeq ($(wildcard ../../lib/cli.js),) 
	ifeq ($(wildcard ./node_modules/.bin/jison),) 
		echo "### FAILURE: Make sure you have run 'make prep' before as the jison compiler is unavailable! ###"
	else
		JISON = sh node_modules/.bin/jison
	endif
else 
	JISON = node $(wildcard ../../lib/cli.js)
endif 



all: build test

prep: npm-install

npm-install:
	npm install

build: lex-parser.js

lex-parser.js: lex.y lex.l
	$(JISON) -o lex-parser.js lex.y lex.l

test:
	node_modules/.bin/mocha tests/


# increment the XXX <prelease> number in the package.json file: version <major>.<minor>.<patch>-<prelease>
bump:
	npm version --no-git-tag-version prerelease

git-tag:
	node -e 'var pkg = require("./package.json"); console.log(pkg.version);' | xargs git tag





clean:
	-rm -f lex-parser.js
	-rm -rf node_modules/

superclean: clean
	-find . -type d -name 'node_modules' -exec rm -rf "{}" \;





.PHONY: all prep npm-install build test clean superclean bump git-tag
