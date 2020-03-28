local SECP256K1_TYPE_HASH = "0xSECP256K1"
local SECP_CELL_DEP = "0xSECP_DEP"
local UDT_CODE_HASH = "0XUDT_CODE"
local SCRIPT_HASH_TYPE_IS_DATA = 0
local SCRIPT_HASH_TYPE_IS_TYPE = 1

local function filter_secp256k1_by_lock_arg(cell, lock_arg)
  local lock = cell.lock 
  return lock.code_hash == SECP256K1_TYPE_HASH and lock.hash_type == SCRIPT_HASH_TYPE_IS_TYPE and lock.args == lock_arg
end

local function filter_sudt_by_type_arg(cell, sudt_arg)
  local t = cell.type 
  return t.code_hash == UDT_CODE_HASH and t.hash_type == SCRIPT_HASH_TYPE_IS_DATA and t.args == sudt_arg
end

local function query_type_cells()
  return animagus.query_cells(function(cell)
    return cell.data_hash == UDT_CODE_HASH
  end)
end

local function ready()
  local type_cells = query_type_cells()
  return len(type_cells) == 1
end

local function balance(sudt_arg, lock_arg)
  local cells = animagus.query_cells(function(cell)
    return filter_secp256k1_by_lock_arg(cell, lock_arg) and filter_sudt_by_type_arg(cell, lock_arg)
  end)

  local tokens = animagus.map(
    function(cell)
      return animagus.slice(cell.data, 0, 16)
    end,
    cells
  )

  return animagus.reduce(
    function(a, b) return a + b end,
    "0x00000000000000000000000000000000",
    tokens
  )
end

return {
  calls = {
    ready = ready,
    balance = balance
  }
}
