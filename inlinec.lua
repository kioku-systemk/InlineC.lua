-- inlinec.lua
--
-- Cross platform Inline C/Cpp Library
--   modified by kioku / System K
--
-- Original by
--   (c) D.Manura, 2008.
--   Licensed under the same terms as Lua itself (MIT license).
--   http://lua-users.org/wiki/InlineCee
--

local luaIncludePathWin      = [[C:\Lua\include]]
local luaLibraryPathWin      = [[C:\Lua\lib]]
local luaLinkOptionWin       = [[lua52.lib]]
local luaIncludePathMacLinux = [[/usr/local/include]]
local luaLibraryPathMacLinux = [[/usr/local/lib]]
local luaLinkOptionMacLinux  = [[-llua]]
local startFuncName          = 'start'             -- Ex. DLLAPI int start(lua_State * L)
local bitModeWin             = 'x86_amd64'
--[[
	About bitModeWin 
	'x86'       = [32bit compile]
	'x86_amd64' = [32bit->64bit cross compile]
	'amd64'     = [64bit compile]
--]]

local includePath = {}
local libraryPath = {}
local linkOption  = {}

local M = {}

M.debug = false

local preamble = [[

#ifdef __cplusplus
extern "C" {
#endif
#include <lua.h>
#include <lauxlib.h>
#ifdef __cplusplus
}
#endif

#ifdef _WIN32
#include <windows.h>
#ifndef DLLAPI

#ifdef __cplusplus
#define DLLAPI extern "C" __declspec(dllexport)
#else
#define DLLAPI __declspec(dllexport)
#endif

#endif
#else   /* Linux, Mac */

#ifdef __cplusplus
#define DLLAPI extern "C" __attribute__ ((visibility("default")))
#else
#define DLLAPI __attribute__ ((visibility("default")))
#endif

#endif

]]

-- Count number of lines in string.
local function numlines(s)
  return # s:gsub("[^\n]", "")
end

local function getPlatform()
	--- command capture
	function captureRedirectErr(cmd)
		--local f = assert(io.popen(cmd .. ' 2>&1' , 'r'))
		local f = assert(io.popen(cmd, 'r'))
		local s = assert(f:read('*all'))
		f:close()
		s = string.gsub(s, '^%s+', '')
		s = string.gsub(s, '%s+$', '')
		s = string.gsub(s, '[\n\r]+', ' ')
		return s
	end
	if package.config:sub(1,1) == "\\" then
		return 'Windows'
	else
		local plf = captureRedirectErr('uname')
		return plf -- 'Darwin', 'Linux'
	end
end

local myPlatform = getPlatform()
--print('Platform = ', myPlatform)

local function getTempFileName(ext)
	local t = os.tmpname() .. '.' .. ext
	if myPlatform == 'Windows' then
		return os.getenv('TMP') .. t
	end
	return t
end

-- Add lines to string so that any compile errors
-- properly indicate line numbers in this file.
local function adjustlines(src, level, extralines)
  local line = debug.getinfo(level+1,'l').currentline
  return ("\n"):rep(line - numlines(src) - extralines) .. src
end

-- Create temporary file containing text and extension.
local function make_temp_file(text, ext)
  local filename = getTempFileName(ext)
  local fh = assert(io.open(filename, 'w'))
  fh:write(text)
  fh:close()
  return filename
end

-- Create temporary header file with preamble.
-- The preamble is placed in a separate file so as not
-- to increase line numbers in compiler errors.
local pre_filename
local function make_preamble()
  if not pre_filename then
    pre_filename = make_temp_file(preamble, 'h')
  end
  return pre_filename
end

-- Execute command.
local function exec(cmd)
	if (M.debug == true) then print(cmd) end
	local handle = io.popen(cmd)
	local ret = handle:read('*all')
	handle:close()
	if (M.debug == true) then print(ret) end
	return ret
 end

local function getCompilerPath(ext)
	if myPlatform == 'Windows' then
		-- Generate compiler bat
		local batfile =      '@call "' .. os.getenv('VS120COMNTOOLS') .. '..\\..\\VC\\vcvarsall.bat" ' .. bitModeWin .. '\n'
		batfile = batfile .. '@cd ' .. os.getenv('TMP') .. '\n'
		batfile = batfile .. '@set ARGS=' .. '\n'
		batfile = batfile .. '@:check' .. '\n'
		batfile = batfile .. '@if "%1"=="" goto final' .. '\n'
		batfile = batfile .. '@set ARGS=%ARGS% %1' .. '\n'
		batfile = batfile .. '@shift' .. '\n'
		batfile = batfile .. '@goto check' .. '\n'
		batfile = batfile .. '@:final' .. '\n'
		batfile = batfile .. '@cl /nologo /EHsc /MD /O2 /D_WIN32=1 %ARGS%' .. '\n'
		local tempbat = make_temp_file(batfile, 'bat')
		return tempbat

	elseif myPlatform == 'Darwin' then
		if ext == 'cpp' then
			return 'clang++ -O2'
		else
			return 'clang -O2'
		end

	else
		if ext == 'cpp' then
			return 'g++ -O2'
		else
			return 'gcc -O2'
		end
	end
end

local function getDllOption()
	if myPlatform == 'Windows' then
		return '/LD '
	else
		return '-shared '
	end
end


local function getLinkerOption()
	if myPlatform == 'Windows' then
		return '/link '
	else
		return ''
	end
end

local function getOutOption()
	if myPlatform == 'Windows' then
		return '/OUT:'
	else
		return '-o '
	end
end

local function getLinkLibOption()
	local i
	local v
	local lnk = ""
	local lnkOpt
	for i,v in pairs(linkOption) do
		lnk = lnk .. v .. ' '
	end
	return lnk
end

local function getIncludeOption()
	local i
	local v
	local inc = ""
	local incOpt
	if myPlatform == 'Windows' then
		incOpt = '/I'
	else
		incOpt = '-I'
	end
	for i,v in pairs(includePath) do
		inc = inc .. incOpt .. v .. ' '
	end
	return inc
end

local function getLibraryOption()
	local i
	local v
	local lib = ""
	local libOpt
	if myPlatform == 'Windows' then
		libOpt = '/LIBPATH:'
	else
		libOpt = '-L'
	end
	for i,v in pairs(libraryPath) do
		lib = lib .. libOpt .. v .. ' '
	end
	return lib
end

local function getDllExt()
	if myPlatform == 'Windows' then
		return 'dll'
	else
		return 'so'
	end
end

-- Compile C source, returning corresponding Lua function.
-- Function must be named 'start' in C.
local function compileExt(src, ext)
	local cpp = getCompilerPath(ext)

	local incOption = getIncludeOption()
	local libOption = getLibraryOption()
	local CC = cpp .. ' ' .. incOption

	local pre_filename = make_preamble()
	src = ('#include %q\n'):format(pre_filename) .. src
	src = adjustlines(src, 2, 1)

	local dllExt = getDllExt()
	local modname = getTempFileName(dllExt)

	local srcname = make_temp_file(src, ext)
	local dlloption = getDllOption()
	local outoption = getOutOption()
	local lnkoption = getLinkLibOption()
	local cmd = CC .. " " .. dlloption
		cmd = cmd .. " " .. srcname

	local lnkCmd = getLinkerOption() .. ' ' .. lnkoption .. ' ' .. libOption .. ' ' .. outoption .. modname
	cmd = cmd .. " " .. lnkCmd
	exec(cmd)

	--print(modname, startFuncName)
	local func = assert(package.loadlib(modname, startFuncName))
	return func, modname
end
local function compile(src)
	return compileExt(src, "c")
end
local function compile_cpp(src)
	return compileExt(src, "cpp")
end

-----------

local function addIncludePath(path)
	includePath[#includePath + 1] = path
end

local function addLibraryPath(path)
	libraryPath[#libraryPath + 1] = path
end

local function addLinkOption(opt)
	linkOption[#linkOption + 1] = opt
end

-----------

local function getIncludePath()
	return includePath
end

local function getLibraryPath()
	return libraryPath
end

local function getLinkOption()
	return linkOption
end

-----------

local function setIncludePath(path_table)
	includePath = path_table
end

local function setLibraryPath(path_table)
	libraryPath = path_table
end

local function setLinkOption(opt_table)
	linkOption = opt_table
end

------------

if myPlatform == 'Windows' then
	includePath[1] = luaIncludePathWin
	libraryPath[1] = luaLibraryPathWin
	linkOption [1] = luaLinkOptionWin
else
	includePath[1] = luaIncludePathMacLinux
	libraryPath[1] = luaLibraryPathMacLinux
	linkOption [1] = luaLinkOptionMacLinux
end


------------

M.compile        = compile
M.compile_cpp    = compile_cpp

M.addIncludePath = addIncludePath
M.addLibraryPath = addLibraryPath
M.addLinkOption  = addLinkOption

M.getIncludePath = getIncludePath
M.getLibraryPath = getLibraryPath
M.getLinkOption  = getLinkOption

M.setIncludePath = setIncludePath
M.setLibraryPath = setLibraryPath
M.setLinkOption  = setLinkOption


return M
