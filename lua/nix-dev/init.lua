local M = {
	command = {
		"nix",
		"print-dev-env",
		"--extra-experimental-features",
		"'nix-command flake'",
		"--json"
	}
}


M.ignored_variables = {
	"BASHOPTS",
	"HOME",
	"NIX_BUILD_TOP",
	"NIX_ENFORCE_PURITY",
	"NIX_LOG_FD",
	"NIX_REMOTE",
	"PPID",
	"SHELL",
	"SHELLOPTS",
	"SSL_CERT_FILE",
	"TEMP",
	"TEMPDIR",
	"TERM",
	"TMP",
	"TMPDIR",
	"TZ",
	"UID"
}

M.PATH_VARS = {
	PATH = ":",
	XDG_DATA_DIRS = ":",
}


M.EVENTS = {
	PRE = "NixDevPre",
	POST = "NixDevPost",
}


--- Fires an autocommand related to NixDev.
---@param pattern M.events Patter to execute
---@param data table Data to pass to the command
local exec_autocmd = function(pattern, data)
	vim.api.nvim_exec_autocmds("User", {
		pattern = pattern,
		modeline = false,
		data = data
	})
end


--- Try to set the environment key.
--- It ignores anything not to be exported or inside the `ignored_variables`
--- configuration.
--- @param envName String Environment key to set. Example: "DEV_KEY"
--- @param data {type: string, value: string?} From `nix print-dev-env`
local try_setenv = function(envName, data)
	local should_ignore = vim.list_contains(M.ignored_variables, envName)
	should_ignore = should_ignore or data.type ~= "exported"

	if should_ignore then return end

	local sep = M.PATH_VARS[envName]

	-- Check if the env variable is a PATH type
	if sep then
		local path = vim.uv.os_getenv(envName)
		if path then
			vim.uv.os_setenv(envName, data.value .. sep .. path)
		end
	else
		vim.uv.os_setenv(envName, data.value)
	end
end

M.nix_develop = function()
	local curr_path = vim.uv.cwd()
	exec_autocmd(M.EVENTS.PRE, {
		path = curr_path,
		msg = "[INFO] Activating environment",
		cmd = M.command
	})

	vim.system(M.command, {text =true}, function(obj)
		vim.schedule(function() 
			if obj.code ~= 0 then
				vim.notify(string.format("[ERROR] Failed to execute with code %d", obj.code), vim.log.levels.ERROR, {})
				exec_autocmd(M.EVENTS.POST,{
					path = curr_path,
					errmsg = obj.stderr,
					error = true,
				})
				return
			end
			local stdout = obj.stdout
			local ok, data= pcall(vim.json.decode, stdout)

			if not ok then
				print("Error, not ok")
				exec_autocmd(M.EVENTS.POST,{
					path = curr_path,
					errmsg = "[ERROR] Could not decode output from command",
					error = true,
				})
				return
			end

			local vars  = data["variables"]

			if not vars then
				exec_autocmd(M.EVENTS.POST,{
					path = curr_path,
					errmsg = "[ERROR] No 'variables' found",
					error = true,
				})
				return
			end

			for envName,data in pairs(vars) do
				try_setenv(envName, data)
			end

			exec_autocmd(M.EVENTS.POST,{
				path = curr_path,
				msg = "[INFO] Succesfully activated environment"
			})
		end)
	end)

end



M.setup = function(opts)
	local ignored_variables = opts.ignored_variables or {}
	local path_vars = opts.path_vars or {}
	M.ignored_variables = vim.tbl_deep_extend('force', M.ignored_variables, ignored_variables)
	M.PATH_VARS = vim.tbl_deep_extend('force', M.PATH_VARS, path_vars)
	M.command = opts.command or M.command

end


return M
