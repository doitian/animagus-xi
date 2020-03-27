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

.PHONY: default test test-dot
