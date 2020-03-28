# animagus-lua

A lua compiler which target is the Animagus AST.

![animagus-lua flowchart](https://raw.githubusercontent.com/doitian/assets/master/2020/0yO15v/chart.png)

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
lua5.1 compiler.lua main.lua
```

The parameter `main.lua` is the path to the input lua file. The compiler will print the
Animagus AST JSON on screen.

## Disclaimer

This project is built in a Hackathon. The `compiler.lua` contains many tricks and is just enough to compile simple UDT example.

## Example

See examples.

```
lua5.1 animagus-lua/compiler.lua animagus-lua/examples/balance.lua | jq .
```

```json
{
  "streams": [],
  "calls": [
    {
      "name": "balance",
      "result": {
        "children": [
          {
            "t": "REDUCER"
          },
          {
            "u": 0,
            "t": "UINT64"
          },
          {
            "children": [
              {
                "t": "MAPPER"
              },
              {
                "children": [
                  {
                    "t": "FILTER"
                  }
                ],
                "t": "QUERY_CELLS"
              }
            ],
            "t": "MAP"
          }
        ],
        "t": "REDUCE"
      }
    }
  ]
}
```

## MetaLua AST

[※ source](https://github.com/fab13n/metalua/blob/master/README-parser.md)

```
block: { stat* }

stat:
  `Do{ stat* }
| `Set{ {lhs+} {expr+} }                    -- lhs1, lhs2... = e1, e2...
| `While{ expr block }                      -- while e do b end
| `Repeat{ block expr }                     -- repeat b until e
| `If{ (expr block)+ block? }               -- if e1 then b1 [elseif e2 then b2] ... [else bn] end
| `Fornum{ ident expr expr expr? block }    -- for ident = e, e[, e] do b end
| `Forin{ {ident+} {expr+} block }          -- for i1, i2... in e1, e2... do b end
| `Local{ {ident+} {expr+}? }               -- local i1, i2... = e1, e2...
| `Localrec{ ident expr }                   -- only used for 'local function'
| `Goto{ <string> }                         -- goto str
| `Label{ <string> }                        -- ::str::
| `Return{ <expr*> }                        -- return e1, e2...
| `Break                                    -- break
| apply

expr:
  `Nil  |  `Dots  |  `True  |  `False
| `Number{ <number> }
| `String{ <string> }
| `Function{ { ident* `Dots? } block }
| `Table{ ( `Pair{ expr expr } | expr )* }
| `Op{ opid expr expr? }
| `Paren{ expr }       -- significant to cut multiple values returns
| apply
| lhs

apply:
  `Call{ expr expr* }
| `Invoke{ expr `String{ <string> } expr* }

ident: `Id{ <string> }

lhs: ident | `Index{ expr expr }

opid: 'add'   | 'sub'   | 'mul'   | 'div'
    | 'mod'   | 'pow'   | 'concat'| 'eq'
    | 'lt'    | 'le'    | 'and'   | 'or'
    | 'not'   | 'len'
```
