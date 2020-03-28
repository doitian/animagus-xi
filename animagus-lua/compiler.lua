local json = require "json"
local MetaluaCompiler = require "metalua.compiler"

local STAT_TAGS = {
  Do = true,
  Set = true,
  While = true,
  Repeat = true,
  If = true,
  Fornum = true,
  Forin = true,
  Local = true,
  Localrec = true,
  Goto = true,
  Label = true,
  Return = true,
  Break = true
}

local OP_TABLE = {
  add = "ADD",
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

local animagus = {}

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

local Scope = {}

function Scope.new(parent_scope)
  local scope = { vars = {}, parent = parent_scope, ret = nil }
  setmetatable(scope, { __index = Scope })
  if parent_scope ~= nil then
    setmetatable(scope.vars, { __index = parent_scope.vars })
  end
  return scope
end

function Scope:push()
  return Scope.new(self)
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
  local scope = self:push()
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
  local scope = parent_scope:push()
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
    local var = self.vars[expr[1]]
    var.compiled = var.compiled or self:compile_expr(var.expr)
    return var.compiled
  end
  if expr.tag == "Call" then
    -- `Call{ expr expr* }
    local callee = assert(self:resolve_expr(expr[1]), "Unknown callee " .. ast_tostring(expr[1]))
    if type(callee) == "function" then
      return callee(self, unpack(expr, 2))
    else
      assert(false, "Function not allowed here " .. ast_tostring(expr))
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
    if index[1] == "capacity" then
      assert(target.t == "ARG")
      return { t = "GET_CAPACITY", children = target }
    end
    if index[1] == "lock" then
      assert(target.t == "ARG")
      return { t = "GET_LOCK", children = target }
    end
    if index[1] == "code_hash" then
      assert(target.t == "ARG" or target.t == "GET_LOCK")
      return { t = "GET_CODE_HASH", children = target }
    end
    if index[1] == "hash_type" then
      assert(target.t == "ARG" or target.t == "GET_LOCK")
      return { t = "GET_HASH_TYPE", children = target }
    end
    if index[1] == "args" then
      assert(target.t == "ARG" or target.t == "GET_LOCK" or target.t == "GET_TYPE")
      return { t = "GET_ARGS", children = target }
    end
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
    local scope = callee.scope:push()
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

local format = "proto"
local input_path
main(arg[1], arg[2])
