local animagus = {}

function animagus.reduce(reducer, init, list)
  local acc = init
  for _, v in ipairs(list) do
    acc = reducer(acc, v)
  end
  return acc
end

function animagus.map(transform, list)
  local res = {}
  for i, v in ipairs(list) do
    res[i] = transform(v)
  end

  return res
end

function animagus.query_cells(filter)
  local cell = {
    capacity = 10,
    lock = {
      code_hash = SECP256K1_TYPE_HASH,
      hash_type = SCRIPT_HASH_TYPE_IS_TYPE,
      args = "0x",
    }
  }

  if filter(cell) then
    return { cell }
  else
    return {}
  end
end

return animagus
