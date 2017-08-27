
JISON_VERSION := $(shell node ../../lib/cli.js -V 2> /dev/null )

ifndef JISON_VERSION 
	JISON = sh node_modules/.bin/jison
else 
	JISON = node ../../lib/cli.js
endif 




all: build test

prep: npm-install

npm-install:
	npm install

npm-update:
	ncu -a --packageFile=package.json

build:
ifeq ($(wildcard ./node_modules/.bin/jison),) 
	$(error "### FAILURE: Make sure you have run 'make prep' before as the jison compiler is unavailable! ###")
endif
	$(JISON) -o lex-parser.js lex.y lex.l

test:
	node_modules/.bin/mocha tests/


# increment the XXX <prelease> number in the package.json file: version <major>.<minor>.<patch>-<prelease>
bump:
	npm version --no-git-tag-version prerelease

git-tag:
	node -e 'var pkg = require("./package.json"); console.log(pkg.version);' | xargs git tag

publish: 
	npm run pub 






clean:
	-rm -f lex-parser.js
	-rm -rf node_modules/
	-rm -f package-lock.json

superclean: clean
	-find . -type d -name 'node_modules' -exec rm -rf "{}" \;





.PHONY: all prep npm-install build test clean superclean bump git-tag publish npm-update

