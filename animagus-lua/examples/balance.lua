local SECP256K1_TYPE_HASH = "0x9bd7e06f3ecf4be0f2fcd2188b23f1b9fcc88e5d4b65a8637b17723bbda3cce8"
local SCRIPT_HASH_TYPE_IS_DATA = 0
local SCRIPT_HASH_TYPE_IS_TYPE = 1

local function make_query_condition(lock_arg)
  return function(cell)
    local lock = cell.lock 
    return lock.code_hash == SECP256K1_TYPE_HASH and lock.hash_type == SCRIPT_HASH_TYPE_IS_TYPE and lock.args == lock_arg
  end
end

local function balance(lock_arg)
  return ast.reduce(
    function(a, b) return a + b end,
    0,
    ast.map(
      function(e) return e.capacity end,
      ast.query_cells(make_query_condition(lock_arg))
    )
  )
end

return {
  calls = {
    balance = balance
  }
}
