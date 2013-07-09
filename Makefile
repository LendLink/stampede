test:
	mocha --compilers coffee:coffee-script -R spec ./test/test.coffee

.PHONY: test