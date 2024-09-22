-- TODO: Make this async

local M = {}
local curl = require("plenary.curl")
local json = vim.json --require("cjson")

-- Default configuration
local default_config = {
	use_ai = false,
	ai_provider = "openai", -- Can be "openai" or "gemini"
	openai_api_key = "",
	gemini_api_key = "",
	command_name = "GitCommitPush",
	keymaps = {
		commit_and_push = "<leader>gcp",
		commit = "<leader>gc",
		push = "<leader>gp",
	},
}

local config = {}

local function notify(message, level)
	vim.notify(message, level, {
		title = "Git Commit Push",
		timeout = 3000,
	})
end

local function get_openai_commit_message(diff)
	local response = curl.post("https://api.openai.com/v1/chat/completions", {
		headers = {
			["Content-Type"] = "application/json",
			["Authorization"] = "Bearer " .. config.openai_api_key,
		},
		body = json.encode({
			model = "gpt-3.5-turbo",
			messages = {
				{
					role = "system",
					content = "You are a helpful assistant that generates concise and informative git commit messages.",
				},
				{
					role = "user",
					content = "Generate a concise git commit message for the following changes:\n\n" .. diff,
				},
			},
			max_tokens = 60,
		}),
	})

	if response.status ~= 200 then
		notify("Error calling OpenAI API: " .. response.body, vim.log.levels.ERROR)
		return nil
	end

	local decoded_response = json.decode(response.body)
	return decoded_response.choices[1].message.content:gsub("^%s*(.-)%s*$", "%1") -- Trim whitespace
end

local function get_gemini_commit_message(diff)
	local response = curl.post(
		"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent?key="
			.. config.gemini_api_key,
		{
			headers = {
				["Content-Type"] = "application/json",
			},
			body = json.encode({
				contents = {
					{
						parts = {
							{
								text = "You are a helpful assistant that generates concise and informative git commit messages. Generate a concise git commit message for the following changes:\n\n"
									.. diff,
							},
						},
					},
				},
				generationConfig = {
					maxOutputTokens = 60,
				},
			}),
		}
	)

	if response.status ~= 200 then
		notify("Error calling Gemini API: " .. response.body, vim.log.levels.ERROR)
		return nil
	end

	local decoded_response = json.decode(response.body)
	return decoded_response.candidates[1].content.parts[1].text:gsub("^%s*(.-)%s*$", "%1") -- Trim whitespace
end

local function get_commit_message()
	if config.use_ai then
		-- Get git diff
		local handle = io.popen("git diff --cached")
		local diff = handle:read("*a")
		handle:close()

		local commit_message
		if config.ai_provider == "openai" then
			commit_message = get_openai_commit_message(diff)
		elseif config.ai_provider == "gemini" then
			commit_message = get_gemini_commit_message(diff)
		else
			notify("Invalid AI provider specified. Using manual input.", vim.log.levels.WARN)
			return vim.fn.input("Enter commit message: ")
		end

		if commit_message then
			notify("AI-generated commit message: " .. commit_message, vim.log.levels.INFO)
			return commit_message
		else
			return vim.fn.input("Enter commit message: ")
		end
	else
		return vim.fn.input("Enter commit message: ")
	end
end

local function execute_command(command)
	local handle = io.popen(command .. " 2>&1")
	local result = handle:read("*a")
	local success = handle:close()
	return success, result
end

function M.commit()
	-- Get the commit message
	local commit_message = get_commit_message()

	if commit_message == "" then
		notify("Commit message cannot be empty. Aborting.", vim.log.levels.WARN)
		return
	end

	-- Stage all changes
	local stage_success, stage_result = execute_command("git add .")
	if not stage_success then
		notify("Error staging changes: " .. stage_result, vim.log.levels.ERROR)
		return
	end

	-- Commit changes
	local commit_success, commit_result =
		execute_command(string.format('git commit -m "%s"', commit_message:gsub('"', '\\"')))
	if not commit_success then
		notify("Error committing changes: " .. commit_result, vim.log.levels.ERROR)
		return
	end
	notify(commit_result, vim.log.levels.INFO)
end

function M.push()
	-- Push all branches to origin
	local push_success, push_result = execute_command("git push --all origin")
	if not push_success then
		notify("Error pushing changes: " .. push_result, vim.log.levels.ERROR)
		return
	end
	notify(push_result, vim.log.levels.INFO)
end

function M.commit_and_push()
	M.commit()
	M.push()
end

function M.setup(opts)
	-- Merge user options with default config
	config = vim.tbl_deep_extend("force", default_config, opts or {})

	-- Register commands
	vim.api.nvim_create_user_command(config.command_name, function()
		M.commit_and_push()
	end, {})
	vim.api.nvim_create_user_command("GitCommit", function()
		M.commit()
	end, {})
	vim.api.nvim_create_user_command("GitPush", function()
		M.push()
	end, {})

	-- Register keyboard shortcuts
	vim.keymap.set(
		"n",
		config.keymaps.commit_and_push,
		M.commit_and_push,
		{ noremap = true, silent = true, desc = "Commit and push changes" }
	)
	vim.keymap.set("n", config.keymaps.commit, M.commit, { noremap = true, silent = true, desc = "Commit changes" })
	vim.keymap.set("n", config.keymaps.push, M.push, { noremap = true, silent = true, desc = "Push changes" })
end

return M
