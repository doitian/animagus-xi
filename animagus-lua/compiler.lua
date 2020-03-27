STAT_TAGS = {
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
	for k,v in ipairs(ast) do
		table.insert(res,white .. ast_tostring(v, a + 1))
	end
	white = white:sub(3)
	table.insert(res,white .. "}")
	return table.concat(res, "\n")
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
  if expr.tag == "Id" then
    var = self.vars[expr[1]]
    var.compiled = var.compiled or self:compile_call(var.expr)
    return var.compiled
  end
  if expr.tag == "Function" then
    for i, ident in ipairs(expr[1]) do
      if ident.tag == "Id" then
        self.vars[ident] = { compiled = { t = "PARAM", u = i - 1 } }
      end
    end
    scope = self:push()
    for _, stat in ipairs(expr[2]) do
      scope:eval_stat(stat)
    end
    return scope:compile_expr(scope.ret.expr[1])
  end
  assert(false, "unknown compile_call " .. tostring(expr.tag) .. ": " .. ast_tostring(expr))
end

function Scope:compile_reduce(reducer, initial, list)
  return {
    t = "REDUCE",
    children = {
      self:compile_reducer(reducer),
      self:compile_expr(initial),
      self:compile_expr(list)
    }
  }
end

function Scope:compile_map(transform, list)
  return {
    t = "MAP",
    children = {
      self:compile_mapper(transform),
      self:compile_expr(list)
    }
  }
end

function Scope:compile_query_cells(filter)
  return {
    t = "QUERY_CELLS",
    children = {
      self:compile_cell_filter(filter)
    }
  }
end

function Scope:compile_reducer(reducer)
  -- TODO
  return { t = "REDUCER" }
end

function Scope:compile_mapper(mapper)
  -- TODO
  return { t = "MAPPER" }
end

function Scope:compile_cell_filter(filter)
  -- TODO
  return { t = "FILTER" }
end

function Scope:compile_expr(expr)
  if expr.tag == "Call" then
    if expr[1][1][1] == "animagus" then
      local method = "compile_" .. expr[1][2][1]
      assert(self[method], "Unknown ast call " .. ast_tostring(expr))
      return self[method](self, unpack(expr, 2))
    end

    assert(expr[1].tag == "Id")
    -- TODO
    -- self:call(unpack(expr))
    return {todo=true}
  end
  if expr.tag == "Number" then
    return { t = "UINT64", u = expr[1] }
  end

  assert(false, "unknown compile_expr " .. tostring(expr.tag) .. ": " .. ast_tostring(expr))
end

function main(input_path, output_path, format)
  local mlc = require 'metalua.compiler'.new()
  local ast = mlc:srcfile_to_ast(input_path)

  local root_scope = Scope.new()

  for _, stat in ipairs(ast) do
    root_scope:eval_stat(stat)
  end

  local root_ast = root_scope.ret.expr[1]
  assert(root_ast and root_ast.tag == "Table")

  animagus_ast = {
    calls = {},
    streams = {}
  }

  for _, kv in ipairs(root_ast) do
    assert(kv.tag == "Pair")
    if kv[1][1] == "calls" then
      for _, call_pair in ipairs(kv[2]) do
        assert(call_pair.tag == "Pair")
        k, v = unpack(call_pair)
        assert(k.tag == "String")
        table.insert(animagus_ast.calls, { name = k[1], result = root_scope:compile_call(v) })
      end
    end
  end

  local json = require "json"
  print(json.encode(animagus_ast))
end

local format = "proto"
local input_path
main(arg[1], arg[2])
