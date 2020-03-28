default: test

test: test-dot

test-dot: animagus-dot/simple_udt.bin animagus-dot/balance.bin
	animagus-dot/x.sh

animagus/examples/udt/simple_udt.bin:
	cd animagus/examples/udt/ && go run generate_ast.go

animagus/examples/balance/balance.bin:
	cd animagus/examples/balance/ && go run generate_ast.go

animagus-dot/simple_udt.bin: animagus/examples/udt/simple_udt.bin
	cp $< $@

animagus-dot/balance.bin: animagus/examples/balance/balance.bin
	cp $< $@

clean:
	rm -f animagus-dot/*.pdf animagus-dot/*.bin animagus-dot/*.dot

check-lua-global:
	! luac -p -l animagus-lua/compiler.lua | grep 'SETTABUP.*_ENV' | grep -v '_ENV "\(ipairs\|assert\|pairs\|unpack\|tostring\|require\|arg\|table\|setmetatable\|type\|print\)"'

stat:
	wc -l -c animagus-dot/main.go animagus-lua/compiler.lua animagus-lua/examples/*

step1: clean test

step2: stat

step3:
	lua5.1 animagus-lua/compiler.lua animagus-lua/examples/balance.lua | jq .

step4:
	lua5.1 animagus-lua/compiler.lua animagus-lua/examples/simple_udt.lua | jq .

.PHONY: default test test-dot clean stat step1 step2 step3 step4
