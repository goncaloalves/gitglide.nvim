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
--
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

		print(command, " Command exit code: ", code)
		print(command, " Stdout: ", stdout_data)
		print(command, " Stderr: ", stderr_data)

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
	curl.post("https://api.openai.com/v1/chat/completions", {
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

	print(str1 .. diff)
	curl.post(
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
								text = [[You are a meticulous and insightful code reviewer tasked with generating precise and informative Git commit messages. 

Analyze the following code changes and craft a commit message that accurately reflects the modifications made. 

The commit message should:

* **Clearly and concisely summarize the specific changes made in the code.** Avoid generic statements like "updated code" or "fixed bug". Instead, specify what was updated and how, or what bug was fixed and the approach taken.
* **Indicate the files or modules affected by the changes.** For example, mention if the changes relate to the UI, backend logic, or specific components.
* **Explain the motivation behind the changes if it's not immediately obvious.** For example, if a refactor was performed, briefly explain the benefits of the new structure.
* **Maintain a professional and informative tone.** 
  **Generate a Git commit message based on the above code changes.  Adhere to the conventional Git commit message format:
  ** **Code Changes:**
  ]] .. diff,
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
		execute_command("git diff --cached", function(success, stdout, stderr) -- Use execute_command here
			if not success then
				notify("Error getting git diff: " .. stderr, vim.log.levels.ERROR)
				callback(nil)
				return
			end

			print(stdout)

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
		vim.schedule(function()
			callback(vim.fn.input("Enter commit message: "))
		end)
	end
end

function M.commit()
	get_commit_message(function(commit_message)
		if commit_message == "" then
			notify("Commit message cannot be empty. Aborting.", vim.log.levels.WARN)
			return
		end

		execute_command("git add .", function(success, stdout, stderr)
			if not success then
				notify("Error staging changes: " .. stderr, vim.log.levels.ERROR)
				return
			end

			execute_command(
				string.format('git commit -m "%s"', commit_message:gsub('"', '\\"')),
				function(success, stdout, stderr)
					if not success then
						notify("Error committing changes: " .. stderr, vim.log.levels.ERROR)
						return
					end
					notify(stdout, vim.log.levels.INFO)
				end
			)
		end)
	end)
end

function M.push()
	execute_command("git push --all origin", function(success, stdout, stderr)
		if not success then
			notify("Error pushing changes: " .. stderr, vim.log.levels.ERROR)
			return
		end
		notify(stdout, vim.log.levels.INFO)
	end)
end

function M.commit_and_push()
	M.commit()
	vim.defer_fn(function()
		M.push()
	end, 1000) -- Wait for 1 second before pushing to ensure commit is completed
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
