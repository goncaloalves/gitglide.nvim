local M = {}

local function get_commit_message()
	local input = vim.fn.input("Enter commit message: ")
	return input
end

local function execute_command(command)
	local handle = io.popen(command)
	local result = handle:read("*a")
	handle:close()
	return result
end

function M.commit_and_push()
	-- Get the commit message
	local commit_message = get_commit_message()

	if commit_message == "" then
		print("Commit message cannot be empty. Aborting.")
		return
	end

	-- Stage all changes
	execute_command("git add .")

	-- Commit changes
	local commit_result = execute_command('git commit -m "' .. commit_message .. '"')
	print(commit_result)

	-- Push all branches to origin
	local push_result = execute_command("git push --all origin")
	print(push_result)
end

M.setup = function(opts)
	print("Hello from GitGlide!")

	vim.api.nvim_create_user_command("CommitAndPush", M.commit_and_push, {})

	opts = opts or {}
end

return M
