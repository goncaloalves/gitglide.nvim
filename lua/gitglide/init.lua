-- Lines just for testing

local M = {}
local curl = require("plenary.curl")
local json = vim.json

-- Default configuration
local default_config = {
	use_ai = false,
	ai_provider = "openai", -- Can be "openai" or "gemini"
	openai_api_key = "",
	gemini_api_key = "",
	command_name = "GitCommitPush",
	keymaps = {
		commit_and_push = "<leader>gcp",
		commit = "<leader>gcc",
		push = "<leader>gpp",
	},
	debug = false,
}

local config = {}

local function notify(message, level)
	vim.schedule(function()
		vim.notify(message, level, {
			title = "GitGlide",
			timeout = 3000,
		})
	end)
end

local function escape_shell_arg(arg)
	-- Escape double quotes, backslashes, and other special characters
	return '"' .. arg:gsub('"', '\\"'):gsub("'", "\\'"):gsub("\\", "\\\\"):gsub("$", "\\$"):gsub("`", "\\`") .. '"'
end

local function get_api_key(key_name)
	-- 1. Check config object
	if config[key_name] and config[key_name] ~= "" then
		return config[key_name]
	end

	-- 2. Check environment variable
	local env_key = os.getenv(key_name:upper()) -- Convert to uppercase for consistency
	if env_key then
		return env_key
	end

	-- 3. Return nil if not found
	return nil
end

local function execute_command(command, callback)
	local stdout = vim.loop.new_pipe(false)
	local stderr = vim.loop.new_pipe(false)
	local stdout_data = ""
	local stderr_data = ""

	local handle
	handle = vim.loop.spawn("sh", {
		args = { "-c", command },
		stdio = { nil, stdout, stderr },
	}, function(code, signal)
		stdout:read_stop()
		stderr:read_stop()
		stdout:close()
		stderr:close()
		handle:close()

		-- Once the process finishes, callback with the result
		callback(code == 0, stdout_data, stderr_data)
	end)

	vim.loop.read_start(stdout, function(err, data)
		if err then
			vim.notify("Error reading stdout: " .. err, vim.log.levels.ERROR)
			return
		end
		if data then
			stdout_data = stdout_data .. data
		end
	end)

	vim.loop.read_start(stderr, function(err, data)
		if err then
			vim.notify("Error reading stderr: " .. err, vim.log.levels.ERROR)
			return
		end
		if data then
			stderr_data = stderr_data .. data
		end
	end)
end

local function get_openai_commit_message(diff, callback)
	local openai_api_key = get_api_key("openai_api_key")
	if not openai_api_key then
		vim.notify_once(
			"OpenAI API key not found. Check configuration or environment variables.",
			vim.log.levels.ERROR,
			{ title = "GitGlide" }
		)
		callback(nil)
		return
	end
	curl.post("https://api.openai.com/v1/chat/completions", {
		headers = {
			["Content-Type"] = "application/json",
			["Authorization"] = "Bearer " .. openai_api_key, -- config.openai_api_key,
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
		callback = vim.schedule_wrap(function(response)
			if response.status ~= 200 then
				notify("Error calling OpenAI API: " .. response.body, vim.log.levels.ERROR)
				callback(nil)
				return
			end

			local decoded_response = json.decode(response.body)
			local commit_message = decoded_response.choices[1].message.content:gsub("^%s*(.-)%s*$", "%1") -- Trim whitespace
			callback(commit_message)
		end),
	})
end

local function get_gemini_commit_message(diff, callback)
	local gemini_api_key = get_api_key("gemini_api_key")
	if not gemini_api_key then
		vim.notify_once(
			"Gemini API key not found. Check configuration or environment variables.",
			vim.log.levels.ERROR,
			{ title = "GitGlide" }
		)
		callback(nil)
		return
	end

	local str1 = [[
  You are a meticulous and insightful code reviewer tasked with generating precise and informative Git commit messages. 

Analyze the following code changes and craft a commit message that accurately reflects the modifications made. 


The commit message should:

* **Clearly and concisely summarize the specific changes made in the code.** Avoid generic statements like "updated code" or "fixed bug". Instead, specify what was updated and how, or what bug was fixed and the approach taken.
* **Indicate the files or modules affected by the changes.** For example, mention if the changes relate to the UI, backend logic, or specific components.
* **Explain the motivation behind the changes if it's not immediately obvious.** For example, if a refactor was performed, briefly explain the benefits of the new structure.
* **Maintain a professional and informative tone.** 
  **Generate a Git commit message based on the above code changes.  Adhere to the conventional Git commit message format:
  ** **Code Changes:**
  ]]

	if config.debug then
		print(str1 .. diff)
	end

	curl.post(
		"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent?key="
			.. gemini_api_key, --config.gemini_api_key,
		{
			headers = {
				["Content-Type"] = "application/json",
			},
			body = json.encode({
				contents = {
					{
						parts = {
							{
								text = str1 .. diff,
							},
						},
					},
				},
				generationConfig = {
					maxOutputTokens = 60,
				},
			}),
			callback = vim.schedule_wrap(function(response)
				if response.status ~= 200 then
					notify("Error calling Gemini API: " .. response.body, vim.log.levels.ERROR)
					callback(nil)
					return
				end

				local decoded_response = json.decode(response.body)
				local commit_message = decoded_response.candidates[1].content.parts[1].text:gsub("^%s*(.-)%s*$", "%1") -- Trim whitespace
				callback(commit_message)
			end),
		}
	)
end

local function get_commit_message(callback)
	if config.use_ai then
		-- First, execute git diff --cached to get the changes
		execute_command("git diff --cached", function(success, stdout, stderr)
			if not success then
				notify("Error getting git diff: " .. stderr, vim.log.levels.ERROR)
				callback(nil)
				return
			end

			if stdout == "" then
				notify("No staged changes to commit.", vim.log.levels.WARN)
				callback(nil)
				return
			end

			-- After getting the diff, generate the commit message using AI or manual input
			if config.ai_provider == "openai" then
				get_openai_commit_message(stdout, function(commit_message)
					if commit_message then
						notify("OpenAI-generated commit message: " .. commit_message, vim.log.levels.INFO)
						callback(commit_message)
					else
						vim.schedule(function()
							callback(vim.fn.input("Enter commit message: "))
						end)
					end
				end)
			elseif config.ai_provider == "gemini" then
				get_gemini_commit_message(stdout, function(commit_message)
					if commit_message then
						notify("Gemini-generated commit message: " .. commit_message, vim.log.levels.INFO)
						callback(commit_message)
					else
						vim.schedule(function()
							callback(vim.fn.input("Enter commit message: "))
						end)
					end
				end)
			else
				notify("Invalid AI provider specified. Using manual input.", vim.log.levels.WARN)
				vim.schedule(function()
					callback(vim.fn.input("Enter commit message: "))
				end)
			end
		end)
	else
		-- Manual input case
		vim.schedule(function()
			callback(vim.fn.input("Enter commit message: "))
		end)
	end
end

function M.commit(callback)
	if config.debug then
		print("Running Git Commit...")
	end
	-- First, stage the changes (git add .)
	execute_command("git add .", function(add_success, add_stdout, add_stderr)
		if not add_success then
			notify("Error staging changes: " .. add_stderr, vim.log.levels.ERROR)
			if callback then
				callback(false)
			end
			return
		end

		-- After staging, get the commit message (with git diff --cached)
		get_commit_message(function(commit_message)
			if not commit_message or commit_message == "" then
				notify("Commit message cannot be empty. Aborting.", vim.log.levels.WARN)
				if callback then
					callback(false)
				end
				return
			end

			local escaped_commit_message = escape_shell_arg(commit_message)

			-- After getting the commit message, commit the changes (git commit -m)
			execute_command(
				--				string.format("git commit -m %q", commit_message:gsub("\n", "\\n")), --commit_message:gsub('"', '\\"')),
				"git commit -m " .. escaped_commit_message, --
				function(commit_success, commit_stdout, commit_stderr)
					if not commit_success then
						notify("Error committing changes: " .. commit_stderr, vim.log.levels.ERROR)
						if callback then
							callback(false)
						end
						return
					end
					notify("Commit successful!", vim.log.levels.INFO)
					if config.debug then
						print("Git Commit ran with success!")
					end
					if callback then
						callback(true)
					end
				end
			)
		end)
	end)
end

function M.push(callback)
	if config.debug then
		print("Running Git Push...")
	end
	execute_command("git push --all origin", function(success, stdout, stderr)
		if not success then
			notify("Error pushing changes: " .. stderr, vim.log.levels.ERROR)
			if callback then
				callback(false)
			end
			return
		end
		notify("Push successful!", vim.log.levels.INFO)
		if config.debug then
			print("Push successful!")
		end
		if callback then
			callback(true)
		end -- Notify success
	end)
end

function M.commit_and_push()
	M.commit(function(commit_success)
		if commit_success then
			-- Wait for commit to finish before pushing
			if config.debug then
				print("Git Commit ran with success!")
			end
			M.push(function(push_success)
				if push_success and config.debug then
					print("Git Push ran with success!")
				end
			end)
		else
			notify("Commit failed. Push aborted.", vim.log.levels.ERROR)
		end
	end)
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
