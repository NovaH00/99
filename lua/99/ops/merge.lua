local utils = require("99.utils")

--- @class _99.Merge
local Merge = {}

--- @param path string
--- @return string|nil, string|nil
local function read_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil, "failed to open file for reading"
  end
  local content = file:read("*a")
  file:close()
  return content, nil
end

--- @param path string
--- @param content string
--- @return boolean, string|nil
local function write_file(path, content)
  local file = io.open(path, "w")
  if not file then
    return false, "failed to open file for writing"
  end
  local ok, err = file:write(content)
  if not ok then
    file:close()
    return false, err
  end
  file:close()
  return true, nil
end

--- @class _99.Merge.Result
--- @field conflict boolean
--- @field content string

--- Perform a 3-way merge using git merge-file
--- @param base_path string path to base file (original snapshot)
--- @param mine_path string path to mine file (user's current file)
--- @param theirs_path string path to theirs file (agent's edited file)
--- @param result_path string path where merged result will be written
--- @return _99.Merge.Result, string|nil
function Merge.three_way(base_path, mine_path, theirs_path, result_path)
  base_path = vim.fn.fnamemodify(base_path, ":p")
  mine_path = vim.fn.fnamemodify(mine_path, ":p")
  theirs_path = vim.fn.fnamemodify(theirs_path, ":p")
  result_path = vim.fn.fnamemodify(result_path, ":p")

  local work_dir = vim.fs.dirname(base_path)
  if not work_dir or work_dir == "." then
    work_dir = vim.fs.dirname(mine_path)
  end

  local cmd = string.format("cd %s && git merge-file -p %s %s %s 2>&1", work_dir, mine_path, base_path, theirs_path)
  local result = vim.fn.system(cmd)

  local final_content = result
  local has_conflict = final_content:find("^<<<<<<< ", 1, true) ~= nil

  local result_dir = vim.fs.dirname(result_path)
  if result_dir and result_dir ~= "" and not vim.uv.fs_stat(result_dir) then
    vim.fn.mkdir(result_dir, "p")
  end

  local ok, err = write_file(result_path, final_content)
  if not ok then
    return nil, "failed to write result: " .. err
  end

  return {
    conflict = has_conflict,
    content = final_content,
  }, nil
end

return Merge
