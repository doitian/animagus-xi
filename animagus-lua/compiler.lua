local json = require "json"
local MetaluaCompiler = require "metalua.compiler"

local OP_TABLE = {
  add = "ADD",
  sub = "SUBTRACT",
  mul = "MULTIPLY",
  div = "DIVIDE",
  mod = "MOD",
  ["and"] = "AND",
  eq = "EQUAL"
}

local function ast_tostring(ast, a)
  a = a or 0
  local white = ("  "):rep(a+1)
  local str = tostring(ast)
  if str:sub(1, 7) ~= "table: " then
    return str
  end

  local res
  if ast.tag then
    res = { "`" .. ast.tag .. " {" }
  else
    res = { "{" }
  end
  for k, v in ipairs(ast) do
    table.insert(res,white .. ast_tostring(v, a + 1))
  end
  white = white:sub(3)
  table.insert(res,white .. "}")
  return table.concat(res, "\n")
end

local animagus = { G = {} }

function animagus.reduce(scope, reducer, initial, list)
  return {
    t = "REDUCE",
    children = {
      scope:compile_function(reducer),
      scope:compile_expr(initial),
      scope:compile_expr(list)
    }
  }
end

function animagus.map(scope, transform, list)
  return {
    t = "MAP",
    children = {
      scope:compile_function(transform),
      scope:compile_expr(list)
    }
  }
end

function animagus.query_cells(scope, filter)
  return {
    t = "QUERY_CELLS",
    children = {
      scope:compile_function(filter)
    }
  }
end

function animagus.slice(scope, target, start, length)
  return {
    t = "SLICE",
    children = {
      scope:compile_expr(target),
      scope:compile_expr(start),
      scope:compile_expr(length),
    }
  }
end

function animagus.index(scope, pos, target)
  return {
    t = "INDEX",
    children = {
      scope:compile_expr(pos),
      scope:compile_expr(target),
    }
  }
end


function animagus.serialize_to_core(scope, target)
  return {
    t = "SERIALIZE_TO_CORE",
    children = {
      scope:compile_expr(target)
    }
  }
end

function animagus.serialize_to_json(scope, target)
  return {
    t = "SERIALIZE_TO_JSON",
    children = {
      scope:compile_expr(target)
    }
  }
end

local function make_constructor(t, keys)
  return function(scope, tab)
    assert(tab.tag == "Table")
    local children = {}
    for _, p in ipairs(tab) do
      local k, v = unpack(p)
      local pos = assert(keys[k[1]])
      children[pos] = scope:compile_expr(v)
    end
    for _, pos in pairs(keys) do
      children[pos] = children[pos] or nil
    end
    return { t = t, children = children }
  end
end

animagus.transaction = make_constructor("TRANSACTION", {
  inputs = 1,
  outputs = 2,
  cell_deps = 3
})

animagus.cell = make_constructor("CELL", {
  capacity = 1,
  lock = 2,
  type = 3,
  data = 4
})

animagus.script = make_constructor("SCRIPT", {
  code_hash = 1,
  hash_type = 2,
  args = 3,
})

animagus.cell_dep = make_constructor("CELL_DEP", {
  out_point = 1,
  dep_type = 2,
})

animagus.out_point = make_constructor("OUT_POINT", {
  tx_hash = 1,
  index = 2,
})

-- TODO: Uint64 may overflow in Lua
function animagus.ckbytes(scope, number)
  assert(number.tag == "Number")
  return { t = "UINT64", u = number[1] * 100000000 }
end

function animagus.shannons(scope, number)
  return scope:compile_expr(number)
end

function animagus.G.len(scope, expr)
  return {
    t = "LEN",
    children = {
      scope:compile_expr(expr)
    }
  }
end

local Scope = {}

function Scope.new(parent_scope, info)
  local vars = {}
  if parent_scope ~= nil then
    setmetatable(vars, { __index = parent_scope.vars })
  end

  local scope = { info = info, vars = vars, parent = parent_scope, ret = nil }
  setmetatable(scope, { __index = Scope })
  return scope
end

function Scope:push(info)
  return Scope.new(self, info)
end

function Scope:eval_stat(stat)
  if stat.tag == "Local" then
    -- | `Local{ {ident+} {expr+}? }               -- local i1, i2... = e1, e2...
    local idents, exprs = unpack(stat)
    for i, ident in ipairs(idents) do
      assert(ident.tag == "Id")
      self.vars[ident[1]] = { scope = self, expr = exprs[i] }
    end
  elseif stat.tag == "Localrec" then
    -- | `Localrec{ ident expr }                   -- only used for 'local function'
    local idents, exprs = unpack(stat)
    local ident = idents[1]
    local expr = exprs[1]
    assert(ident.tag == "Id", "Invalid Localrec ident " .. ast_tostring(ident))
    self.vars[ident[1]] = { scope = self, expr = expr }
  elseif stat.tag == "Return" then
    -- | `Return{ <expr*> }                        -- return e1, e2...
    self.ret = { scope = self, expr = stat }
  else
    assert(false, "unknown eval_stat " .. tostring(stat.tag) .. ": " .. ast_tostring(stat))
  end
end

function Scope:compile_call(expr)
  expr = self:resolve_expr(expr).expr
  assert(expr.tag == "Function", "invalid compile_call " .. ast_tostring(expr))
  for i, ident in ipairs(expr[1]) do
    if ident.tag == "Id" then
      self.vars[ident[1]] = { compiled = { t = "PARAM", u = i - 1 } }
    end
  end
  local scope = self:push(tostring(expr.lineinfo))
  for _, stat in ipairs(expr[2]) do
    scope:eval_stat(stat)
  end
  return scope:compile_expr(scope.ret.expr[1])
end

function Scope:compile_function(f)
  f = self:resolve_expr(f)
  local parent_scope = f.scope
  local expr = f.expr

  --| `Function{ { ident* `Dots? } block }
  assert(expr.tag == "Function", "Unknown compile_function " .. ast_tostring(expr))
  local scope = parent_scope:push(tostring(expr.lineinfo))
  local args, block = unpack(expr)
  for i, a in ipairs(args) do
    scope.vars[a[1]] = { compiled = { t = "ARG", u = i - 1 } }
  end
  for _, stat in ipairs(block) do
    scope:eval_stat(stat)
  end

  return scope:compile_expr(scope.ret.expr[1])
end

function Scope:compile_expr(expr)
  if expr.tag == "Id" then
    local var = assert(self.vars[expr[1]], "var " .. expr[1] .. " does not exist: " .. tostring(expr.lineinfo))
    var.compiled = var.compiled or var.scope:compile_expr(var.expr)
    return var.compiled
  end
  if expr.tag == "Call" then
    -- `Call{ expr expr* }
    local callee = assert(self:resolve_expr(expr[1]), "Unknown callee " .. ast_tostring(expr[1]))
    if type(callee) == "function" then
      return callee(self, unpack(expr, 2))
    else
      return self:call(callee, expr)
    end
  end
  if expr.tag == "Number" then
    return { t = "UINT64", u = expr[1] }
  end
  if expr.tag == "String" then
    return { t = "BYTES", raw = expr[1] }
  end
  if expr.tag == "Op" then
    local animagus_op = OP_TABLE[expr[1]]
    if animagus_op then
      return { t = animagus_op, children = {
        self:compile_expr(expr[2]),
        self:compile_expr(expr[3])
      }}
    end
  end
  if expr.tag == "Index" then
    local target, index = unpack(expr)

    target = self:compile_expr(target)
    local t = "GET_" .. index[1]:upper()
    return { t = t, children = target }
  end
  if expr.tag == "Table" then
    local children = {}
    for _, e in ipairs(expr) do
      assert(e.tag ~= "Pair", "Associate Table not supported")
      table.insert(children, self:compile_expr(e))
    end
    return { t = "LIST", children = children }
  end
  if expr.tag == "Paren" then
    return self:compile_expr(expr[1])
  end

  assert(false, "unknown compile_expr " .. tostring(expr.tag) .. ": " .. ast_tostring(expr))
end

function Scope:resolve_expr(expr)
  if expr.tag == "Id" then
    local found = self.vars[expr[1]]
    if not found then
      if expr[1] == "animagus" then
        found = animagus
      end
      if expr[1] == "len" then
        found = animagus.G.len
      end
    end
    return found
  end

  if expr.tag == "Index" then
    local tab = assert(self:resolve_expr(expr[1]), "invalid table " .. ast_tostring(expr[1]))
    if tab.expr then
      assert(tab.expr.tag == "Table")
      for _, p in ipairs(tab.expr) do
        local k, v = unpack(p)
        if k[1] == expr[2][1] then
          return { scope = tab.scope, expr = v }
        end
      end
    else
      return tab[expr[2][1]]
    end
  end

  if expr.tag == "Call" then
    local callee = assert(self:resolve_expr(expr[1]))
    assert(callee.expr.tag == "Function")
    local scope = callee.scope:push(tostring(callee.expr.lineinfo))
    local args, block = unpack(callee.expr)
    for i, a in ipairs(args) do
      scope.vars[a[1]] = self:resolve_expr(expr[i + 1])
    end
    for _, stat in ipairs(block) do
      scope:eval_stat(stat)
    end
    return { scope = scope.ret.scope, expr = scope.ret.expr[1] }
  end

  return { scope = self, expr = expr }
end

function Scope:call(callee, call)
  assert(callee.expr.tag == "Function")
  local scope = callee.scope:push(tostring(callee.expr.lineinfo))
  local args, block = unpack(callee.expr)

  for i, a in ipairs(args) do
    scope.vars[a[1]] = self:resolve_expr(call[i + 1])
  end
  for _, stat in ipairs(block) do
    scope:eval_stat(stat)
  end

  return scope:compile_expr(scope.ret.expr[1])
end

local function main(input_path, output_path, format)
  local mlc = MetaluaCompiler.new()
  local ast = mlc:srcfile_to_ast(input_path)

  local root_scope = Scope.new()

  for _, stat in ipairs(ast) do
    root_scope:eval_stat(stat)
  end

  local root_ast = root_scope.ret.expr[1]
  assert(root_ast and root_ast.tag == "Table")

  local animagus_ast = {
    calls = {},
    streams = {}
  }

  for _, kv in ipairs(root_ast) do
    assert(kv.tag == "Pair")
    if kv[1][1] == "calls" then
      for _, call_pair in ipairs(kv[2]) do
        assert(call_pair.tag == "Pair")
        local k, v = unpack(call_pair)
        assert(k.tag == "String")
        table.insert(animagus_ast.calls, { name = k[1], result = root_scope:compile_call(v) })
      end
    end
  end

  print(json.encode(animagus_ast))
end

main(arg[1], arg[2])
