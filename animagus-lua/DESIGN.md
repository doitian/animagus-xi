# Design

The compiler does two things: evaluation and compilation.

![](https://raw.githubusercontent.com/doitian/assets/master/2020/V744V4/animagus-lua-design.png)

## Evaluate Lua statement

The compiler will create nested *Scope* for each Lua scope and function
invocation (stack).

The evaluation will assign the variable table. The child variable table
inherit the parent variable table, so when a variable does not exist in child,
compiler will continue to lookup in ancestor tables.

The compiler does not expand the variable content, the original expression is
saved into to the variable table, as well as the scope used to compile the
expression.

## Compile Lua expression

The compiler transfers the Lua expression to Animagus AST node.

If the expression is a variable access, the variable expression is fetched
from variable table and is compiled using the scope where the expression
occurs.

The variable table also caches the variable compilation result to speedup the
compilation.
