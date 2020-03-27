# animagus-dot

Convert an Animagus AST to Graphviz dot.

Build

```
go build .
```

Usage

```
animagus-dot ast.bin ast.dot
```

It will read AST from file `ast.bin` and write the dot file into `ast.dot`.

A example image generated from [balance
ast](https://github.com/xxuejie/animagus/tree/master/examples/balance)

![](https://raw.githubusercontent.com/doitian/assets/master/2020/baf1Ba/balance.jpg)
