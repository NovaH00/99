-- luacheck: globals describe it assert
local eq = assert.are.same
local Providers = require("99.providers")

describe("providers", function()
  describe("OpenCodeProvider", function()
    it("builds correct command with model", function()
      local request = { model = "anthropic/claude-sonnet-4-5" }
      local cmd =
        Providers.OpenCodeProvider._build_command(nil, "test query", request)
      eq({
        "opencode",
        "run",
        "--agent",
        "build",
        "-m",
        "anthropic/claude-sonnet-4-5",
        "--title",
        "",
        "test query",
      }, cmd)
    end)

    it("has correct default model", function()
      eq(
        "opencode/claude-sonnet-4-5",
        Providers.OpenCodeProvider._get_default_model()
      )
    end)
  end)

  describe("ClaudeCodeProvider", function()
    it("builds correct command with model", function()
      local request = { model = "anthropic/claude-sonnet-4-5" }
      local cmd =
        Providers.ClaudeCodeProvider._build_command(nil, "test query", request)
      eq({
        "claude",
        "--dangerously-skip-permissions",
        "--model",
        "anthropic/claude-sonnet-4-5",
        "--print",
        "test query",
      }, cmd)
    end)

    it("has correct default model", function()
      eq("claude-sonnet-4-5", Providers.ClaudeCodeProvider._get_default_model())
    end)
  end)

  describe("CursorAgentProvider", function()
    it("builds correct command with model", function()
      local request = { model = "anthropic/claude-sonnet-4-5" }
      local cmd =
        Providers.CursorAgentProvider._build_command(nil, "test query", request)
      eq({
        "cursor-agent",
        "--model",
        "anthropic/claude-sonnet-4-5",
        "--print",
        "test query",
      }, cmd)
    end)

    it("has correct default model", function()
      eq("sonnet-4.5", Providers.CursorAgentProvider._get_default_model())
    end)
  end)

  describe("GeminiCLIProvider", function()
    it("builds correct command with model", function()
      local request = { model = "gemini-2.5-pro" }
      local cmd =
        Providers.GeminiCLIProvider._build_command(nil, "test query", request)
      eq({
        "gemini",
        "--approval-mode",
        "auto_edit",
        "--model",
        "gemini-2.5-pro",
        "--prompt",
        "test query",
      }, cmd)
    end)

    it("has correct default model", function()
      eq("auto", Providers.GeminiCLIProvider._get_default_model())
    end)
  end)

  describe("PiProvider", function()
    it("builds correct command with model", function()
      local request = { model = "anthropic/claude-sonnet-4-5" }
      local cmd =
        Providers.PiProvider._build_command(nil, "test query", request)
      eq({
        "pi",
        "--print",
        "--model",
        "anthropic/claude-sonnet-4-5",
        "test query",
      }, cmd)
    end)

    it("builds prompt with line range in snippet tag attribute", function()
      local mock_range = {
        to_text = function()
          return "local x = 1\nlocal y = 2"
        end,
        start = { to_vim = function() return 5, 0 end },
        end_ = { to_vim = function() return 6, 11 end },
      }
      local context = {
        user_prompt = "refactor this",
        full_path = "/path/to/file.lua",
        data = { type = "visual", range = mock_range },
      }
      local prompt = Providers.PiProvider._build_prompt(context)
      eq(
        [[Edit the file below using your edit tool. Apply a "fill in the middle" change: keep the surrounding context unchanged, but modify the snippet according to the instruction.

<file>/path/to/file.lua</file>

<snippet_to_replace lines="5-6">
local x = 1
local y = 2
</snippet_to_replace>

<instruction>
refactor this
</instruction>

<edit_strategy>
The edit tool REPLACES oldText with newText. oldText is deleted, newText takes its place.
- Choose oldText to be unique enough to match exactly what you want to change.
- newText is the full replacement — it completely substitutes oldText.
- NEVER use oldText as just a "marker" with newText as additional content.

Examples:

1. Adding a docstring to a function (oldText includes the function line, newText has docstring + function):
   oldText = "def foo(x):\n    return x + 1"
   newText = "def foo(x):\n    \"\"\"Add one to x.\"\"\"\n    return x + 1"

2. Changing a function signature (oldText = old sig, newText = new sig + same body):
   oldText = "def foo(x):\n    return x + 1"
   newText = "def foo(x: int) -> int:\n    return x + 1"

3. Modifying a variable assignment:
   oldText = "count = 0"
   newText = "count = 10"

4. Removing a line:
   oldText = "print('debug')"
   newText = ""
</edit_strategy>

<tool_usage>
- Your first read call does NOT need an offset; it returns ~2k lines or 50KB by default.
- If that doesn't show enough context, read again with line offsets to fetch surrounding sections.
- You may call the read tool as many times as needed to understand the file and codebase structure.
- Do not hesitate to explore; thorough context gathering leads to correct edits.
- If an edit fails, ALWAYS use the read tool first to investigate what went wrong before retrying.
- Use bash for exploration (grep, ls, find) if you need to navigate the codebase.
</tool_usage>

<edit_rules>
- Each oldText must be UNIQUE and exactly match the original file content.
- All edits are applied against the original file simultaneously, NOT incrementally.
- Merge nearby or related changes into a single edit; do not emit overlapping edits.
- Do NOT include large unchanged blocks just to connect distant changes.
- Preserve exact indentation, whitespace, and formatting of unchanged lines.
</edit_rules>]],
        prompt
      )
    end)

    it("has correct default model", function()
      eq(
        "anthropic/claude-sonnet-4-5",
        Providers.PiProvider._get_default_model()
      )
    end)

    it("parses models from --list-models output", function()
      local models = {}
      local stdout =
        "provider            model        context  max-out  thinking  images\nllama.cpp-original  local-model  128K     16.4K    no        no\nllama.cpp-proxied   local-model  128K     16.4K    no        no"
      local lines = vim.split(stdout, "\n", { trimempty = true })
      for i = 2, #lines do
        local parts = vim.split(lines[i], "%s+")
        if #parts >= 2 then
          table.insert(models, parts[1] .. "/" .. parts[2])
        end
      end
      eq({
        "llama.cpp-original/local-model",
        "llama.cpp-proxied/local-model",
      }, models)
    end)
  end)

  describe("provider integration", function()
    it("can be set as provider override", function()
      local _99 = require("99")

      _99.setup({ provider = Providers.ClaudeCodeProvider })
      local state = _99.__get_state()
      eq(Providers.ClaudeCodeProvider, state.provider_override)
    end)

    it(
      "uses OpenCodeProvider default model when no provider or model specified",
      function()
        local _99 = require("99")

        _99.setup({})
        local state = _99.__get_state()
        eq("opencode/claude-sonnet-4-5", state.model)
      end
    )

    it(
      "uses ClaudeCodeProvider default model when provider specified but no model",
      function()
        local _99 = require("99")

        _99.setup({ provider = Providers.ClaudeCodeProvider })
        local state = _99.__get_state()
        eq("claude-sonnet-4-5", state.model)
      end
    )

    it(
      "uses CursorAgentProvider default model when provider specified but no model",
      function()
        local _99 = require("99")

        _99.setup({ provider = Providers.CursorAgentProvider })
        local state = _99.__get_state()
        eq("sonnet-4.5", state.model)
      end
    )

    it(
      "uses GeminiCLIProvider default model when provider specified but no model",
      function()
        local _99 = require("99")

        _99.setup({ provider = Providers.GeminiCLIProvider })
        local state = _99.__get_state()
        eq("auto", state.model)
      end
    )

    it("uses custom model when both provider and model specified", function()
      local _99 = require("99")

      _99.setup({
        provider = Providers.ClaudeCodeProvider,
        model = "custom-model",
      })
      local state = _99.__get_state()
      eq("custom-model", state.model)
    end)
  end)

  describe("provider_extra_args", function()
    it("stores provider_extra_args on state", function()
      local _99 = require("99")
      _99.setup({
        provider_extra_args = { "--no-session-persistence" },
      })
      local state = _99.__get_state()
      eq({ "--no-session-persistence" }, state.provider_extra_args)
    end)

    it("defaults provider_extra_args to empty table", function()
      local _99 = require("99")
      _99.setup({})
      local state = _99.__get_state()
      eq({}, state.provider_extra_args)
    end)
  end)

  describe("BaseProvider", function()
    it("all providers have make_request", function()
      eq("function", type(Providers.OpenCodeProvider.make_request))
      eq("function", type(Providers.ClaudeCodeProvider.make_request))
      eq("function", type(Providers.CursorAgentProvider.make_request))
      eq("function", type(Providers.GeminiCLIProvider.make_request))
    end)
  end)
end)
