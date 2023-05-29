vim.fn.sign_define("test_passed", { text = "●", texthl = "Green" })
vim.fn.sign_define("test_failed", { text = "●", texthl = "Error" })
vim.fn.sign_define("test_progress", { text = "W", texthl = "Warnings" })
vim.fn.sign_define("test_pending", { text = "○", texthl = "Warnings" })

local spinner_timer = nil
local spinner_symbols = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local current_spinner_index = 1

local function is_buffer_visible(bufnr)
  local info = vim.fn.getbufinfo(bufnr)
  for _, bufinfo in ipairs(info) do
    if (#bufinfo.windows > 0) then
      return true
    end
  end

  return false
end

local function is_buffer_test_file(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  return string.find(name, '.spec') and true or false
end

local function list_testable_buffers()
  local result = {}
  local buffers = vim.api.nvim_list_bufs()
  for _, buffer in ipairs(buffers) do
    if is_buffer_test_file(buffer) and is_buffer_visible(buffer) then
      table.insert(result, buffer)
    end
  end

  return result
end

local function process_jest_output(bufnr, data)
  for _, testResult in ipairs(data.testResults) do
    for _, assertionResult in ipairs(testResult.assertionResults) do
      local title = assertionResult.title
      local status = assertionResult.status
      local line = vim.api.nvim_buf_call(bufnr, function()
        return vim.fn.search(title, "n")
      end)
      if line > 0 then
        if status == "passed" then
          vim.fn.sign_place(0, "test_sign", "test_passed", bufnr, { lnum = line })
        elseif status == "pending" then
          vim.fn.sign_place(0, "test_sign", "test_pending", bufnr, { lnum = line })
        elseif status == "failed" then
          vim.fn.sign_place(0, "test_sign", "test_failed", bufnr, { lnum = line })
        end
      end
    end
  end
end

local function spinner()
  vim.fn.sign_define("test_progress", { text = spinner_symbols[current_spinner_index], texthl = "Warnings" })
  current_spinner_index = (current_spinner_index + 1) % #spinner_symbols
end

local function start_spinner()
  if spinner_timer == nil then
    spinner_timer = vim.loop.new_timer()
  end

  spinner_timer:start(100, 100, vim.schedule_wrap(spinner))
end

local function stop_spinner()
  spinner_timer:stop()
end


local function start_wait(bufnr)
  local responses = vim.fn.sign_getplaced(bufnr, { group = "test_sign" })

  for _, response in ipairs(responses) do
    for _, sign in ipairs(response.signs) do
      vim.fn.sign_place(sign.id, sign.group, "test_progress", bufnr)
    end
  end
  start_spinner()
end


local function clear_signs(bufnr)
  vim.fn.sign_unplace("test_sign", { buffer = bufnr })
end

local function stop_wait(bufnr)
  clear_signs(bufnr)
  stop_spinner()
end

local function run_test(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)

  start_wait(bufnr)

  vim.fn.jobstart("npm run --silent test -- --json " .. name, {
    async = true,
    on_stdout = function(_, data)
      local raw = vim.fn.join(data, '\n')
      local result = vim.fn.json_decode(raw)
      stop_wait(bufnr)
      process_jest_output(bufnr, result)
    end,
    stdout_buffered = true
  })
end

local function run_tests()
  local buffers = list_testable_buffers()
  for _, bufnr in ipairs(buffers) do
    run_test(bufnr)
  end
end

local function setup(user_settings)
  local cmdGrp = vim.api.nvim_create_augroup("nvim-test-runner", { clear = true })
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
    group = cmdGrp,
    pattern = "*",
    callback = run_tests
  })
end

return {
  run_tests = run_tests,
  setup = setup,
}
