local SCRIPT_HASH_TYPE_IS_DATA = 0
local SCRIPT_HASH_TYPE_IS_TYPE = 1
local CELL_DEP_IS_CODE = 0
local CELL_DEP_IS_DEP_GROUP = 1
local UDT_CODE_HASH = "0x48dbf59b4c7ee1547238021b4869bceedf4eea6b43772e5d66ef8865b6ae7212"
local UDT_ZERO = "0x00000000000000000000000000000000"
local SECP_TYPE_HASH = "0x9bd7e06f3ecf4be0f2fcd2188b23f1b9fcc88e5d4b65a8637b17723bbda3cce8"
local SECP_DEP = animagus.cell_dep({
  out_point = animagus.out_point({
    tx_hash = "0x71a7ba8fc96349fea0ed3a5c47992e3b4084b031a42264a018e0072e8172e46c",
    -- Devnet
    -- TODO: pass env variables to script
    -- local SECP_DEP_GROUP_TX_HASH = "0x6495cede8d500e4309218ae50bbcadb8f722f24cc7572dd2274f5876cb603e4e"
    index = 0
  }),
  dep_type = CELL_DEP_IS_DEP_GROUP
})


local function filter_secp_by_lock_arg(cell, lock_arg)
  local lock = cell.lock 
  return lock.code_hash == SECP_TYPE_HASH and lock.hash_type == SCRIPT_HASH_TYPE_IS_TYPE and lock.args == lock_arg
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

local function query_token_cells(sudt_arg, lock_arg)
  return animagus.query_cells(function(cell)
    return filter_secp_by_lock_arg(cell, lock_arg) and filter_sudt_by_type_arg(cell, sudt_arg)
  end)
end

local function reduce_balance(cells)
  local tokens = animagus.map(
    function(cell)
      return animagus.slice(cell.data, 0, 16)
    end,
    cells
  )

  return animagus.reduce(
    function(a, b) return a + b end,
    UDT_ZERO,
    tokens
  )
end

local function reduce_capacity(cells)
  return animagus.reduce(
    function(a, b) return a + b end,
    0,
    animagus.map(
      function(e) return e.capacity end,
      cells
    )
  )
end

local function estimate_fee(transaction)
  local length = len(animagus.serialize_to_core(transaction))
  return 1 * (length + animagus.shannons(100))
end

local function assemble_lock_script(lock_arg)
  return animagus.script({
    code_hash = SECP_TYPE_HASH,
    hash_type = SCRIPT_HASH_TYPE_IS_TYPE,
    args = lock_arg
  })
end

local function assemble_type_script(type_arg)
  return animagus.script({
    code_hash = UDT_CODE_HASH,
    hash_type = SCRIPT_HASH_TYPE_IS_DATA,
    args = type_arg
  })
end

local function ready()
  local type_cells = query_type_cells()
  return len(type_cells) == 1
end

local function balance(sudt_arg, lock_arg)
  local cells = query_token_cells(sudt_arg, lock_arg)
  return reduce_balance(cells)
end

local function transfer(sudt_arg, from_lock_arg, to_lock_arg, transfer_amount)
  local cells = query_token_cells(sudt_arg, lock_arg)
  local balance = reduce_balance(cells)
  local capacity = reduce_capacity(cells)

  local type_cell = animagus.index(0, query_type_cells())

  local transfer_cell = animagus.cell({
    capacity = animagus.ckbytes(142),
    lock = assemble_lock_script(to_lock_arg),
    type = assemble_type_script(sudt_arg),
    data = UDT_ZERO + transfer_amount
  })

  local change_cell = animagus.cell({
    capacity = capacity - animagus.ckbytes(142),
    lock = assemble_lock_script(from_lock_arg),
    type = assemble_type_script(sudt_arg),
    data = balance - transfer_amount
  })

  local transaction = animagus.transaction({
    inputs = cells,
    outputs = { transfer_cell, change_cell },
    cell_deps = { SECP_DEP, type_cell }
  })

  local fee = estimate_fee(transaction)
  -- recreate transaction by adjust fee
  local adjusted_change_cell = animagus.cell({
    capacity = capacity - animagus.ckbytes(142) - fee,
    lock = assemble_lock_script(from_lock_arg),
    type = assemble_type_script(sudt_arg),
    data = balance - transfer_amount
  })
  local adjusted_transaction = animagus.transaction({
    inputs = cells,
    outputs = { transfer_cell, adjusted_change_cell },
    cell_deps = { SECP_DEP, type_cell }
  })

  return animagus.serialize_to_json(adjusted_transaction)
end

return {
  calls = {
    ready = ready,
    balance = balance,
    transfer = transfer,
  }
}
