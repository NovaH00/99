local RequestStatus = require("99.ops.request_status")
local Mark = require("99.ops.marks")
local geo = require("99.geo")
local make_prompt = require("99.ops.make-prompt")
local CleanUp = require("99.ops.clean-up")
local Merge = require("99.ops.merge")
local utils = require("99.utils")

local make_clean_up = CleanUp.make_clean_up
local make_observer = CleanUp.make_observer

local Range = geo.Range
local Point = geo.Point

local function setup_merge_files(context, data)
  local full_path = context.full_path
  local tmp_dir = context._99:tmp_dir()
  local xid = context.xid

  local base_path = utils.named_tmp_file(tmp_dir, "99-base-" .. xid)
  local agent_path = utils.named_tmp_file(tmp_dir, "99-agent-" .. xid)

  local tmp_dir_stat = vim.uv.fs_stat(tmp_dir)
  if not tmp_dir_stat then
    vim.fn.mkdir(tmp_dir, "p")
  end

  local lines = vim.fn.readfile(full_path)
  if lines and #lines > 0 then
    local base_content = table.concat(lines, "\n")
    if #lines[#lines] ~= "" then
      base_content = base_content .. "\n"
    end

    local base_file = io.open(base_path, "w")
    if base_file then
      base_file:write(base_content)
      base_file:close()
    end

    local agent_file = io.open(agent_path, "w")
    if agent_file then
      agent_file:write(base_content)
      agent_file:close()
    end

    data.base_path = base_path
    data.agent_path = agent_path
  end

  return base_path, agent_path
end

local function perform_three_way_merge(context, data)
  local full_path = context.full_path
  local base_path = data.base_path
  local agent_path = data.agent_path

  if not base_path or not agent_path then
    return false, "merge files not set up"
  end

  local result, err = Merge.three_way(base_path, full_path, agent_path, full_path .. ".merged")
  if err then
    return false, err
  end

  if result.conflict then
    vim.notify(
      "99: Merge completed with conflicts. Review: " .. full_path .. ".merged",
      vim.log.levels.WARN
    )
  end

  local merged_file = io.open(full_path .. ".merged", "r")
  if merged_file then
    local merged_content = merged_file:read("*a")
    merged_file:close()

    vim.fn.writefile(vim.split(merged_content, "\n"), full_path)
    os.remove(full_path .. ".merged")
  end

  if base_path then
    os.remove(base_path)
  end
  if agent_path then
    os.remove(agent_path)
  end

  vim.cmd("checktime")
  return true, nil
end

--- @param context _99.Prompt
--- @param opts? _99.ops.Opts
local function over_range(context, opts)
  opts = opts or {}
  local logger = context.logger:set_area("visual")

  local data = context:visual_data()
  local range = data.range
  local top_mark = Mark.mark_above_range(range)
  local bottom_mark = Mark.mark_point(range.buffer, range.end_)
  context.marks.top_mark = top_mark
  context.marks.bottom_mark = bottom_mark

  logger:debug(
    "visual request start",
    "start",
    Point.from_mark(top_mark),
    "end",
    Point.from_mark(bottom_mark)
  )

  local provider = context._99.provider_override
    or require("99.providers").OpenCodeProvider
  local use_three_way_merge = provider._build_prompt ~= nil

  local base_path, agent_path
  if use_three_way_merge then
    base_path, agent_path = setup_merge_files(context, data)
    logger:debug("3-way merge setup", "base", base_path, "agent", agent_path)
  end

  local display_ai_status = context._99.ai_stdout_rows > 1
  local top_status = RequestStatus.new(
    250,
    context._99.ai_stdout_rows or 1,
    "Implementing",
    top_mark
  )
  local bottom_status = RequestStatus.new(250, 1, "Implementing", bottom_mark)
  local clean_up = make_clean_up(function()
    top_status:stop()
    bottom_status:stop()
  end)

  local system_cmd = context._99.prompts.prompts.visual_selection(range)
  local prompt, refs = make_prompt(context, system_cmd, opts)

  context:add_prompt_content(prompt)
  context:add_references(refs)
  context:add_clean_up(clean_up)

  top_status:start()
  bottom_status:start()
  context:start_request(make_observer(context, {
    on_complete = function(status, response)
      if status == "cancelled" then
        logger:debug("request cancelled for visual selection, removing marks")
        if use_three_way_merge and base_path then
          os.remove(base_path)
        end
        if use_three_way_merge and agent_path then
          os.remove(agent_path)
        end
      elseif status == "failed" then
        logger:error(
          "request failed for visual_selection",
          "error response",
          response or "no response provided"
        )
        if use_three_way_merge and base_path then
          os.remove(base_path)
        end
        if use_three_way_merge and agent_path then
          os.remove(agent_path)
        end
      elseif status == "success" then
        if use_three_way_merge then
          local ok, err = perform_three_way_merge(context, data)
          if not ok then
            logger:error("3-way merge failed", "error", err)
          end
          context._99:sync()
          return
        end

        local valid = top_mark:is_valid() and bottom_mark:is_valid()
        if not valid then
          logger:fatal(
            -- luacheck: ignore 631
            "the original visual_selection has been destroyed.  You cannot delete the original visual selection during a request"
          )
          return
        end

        if vim.trim(response) == "" then
          print("response was empty, visual replacement aborted")
          logger:debug("response was empty, visual replacement aborted")
          return
        end

        local new_range = Range.from_marks(top_mark, bottom_mark)
        local lines = vim.split(response, "\n")

        --- HACK: i am adding a new line here because above range will add a mark to the line above.
        --- that way this appears to be added to "the same line" as the visual selection was
        --- originally take from
        table.insert(lines, 1, "")

        new_range:replace_text(lines)
        context._99:sync()
      end
    end,
    on_stdout = function(line)
      if display_ai_status then
        top_status:push(line)
      end
    end,
  }))
end

return over_range
