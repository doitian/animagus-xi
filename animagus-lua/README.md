# animagus-lua

A lua compiler which target is the Animagus AST.

## Dependencies

* Lua 5.1
* metalua
* json4lua

It is recommended to install dependencies via luarocks. Pay attention to
install the packages into the correct lua version. For example, in macOS:

```
brew install lua@5.1 luarocks
luarocks --lua-dir=/usr/local/opt/lua@5.1 install metalua
luarocks --lua-dir=/usr/local/opt/lua@5.1 install json4lua
```

## Usage

```
eval $(luarocks --lua-dir=/usr/local/opt/lua@5.1 path)
lua5.1 compiler.lua main.lua main.bin
```

- `main.lua` is the path to the input lua file
- `main.bin` is the path to the generated AST file

## Example

See examples.
