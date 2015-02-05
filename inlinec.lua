-- inlinec.lua
--
-- Cross platform Inline C Library
--   modified by kioku / System K
--
-- Original by
--   (c) D.Manura, 2008.
--   Licensed under the same terms as Lua itself (MIT license).
--   http://lua-users.org/wiki/InlineCee
--

local luaIncludePathWin      = [[C:\Lua\include]]
local luaLibraryPathWin      = [[C:\Lua\lib]
local luaIncludePathMacLinux = [[/usr/local/include]]
local luaLibraryPathMacLinux = [[/usr/local/lib]]
local startFuncName          = 'start'             -- Ex. DLLAPI int start(lua_State * L) 
local bitModeWin             = 'x64' -- or x86

local M = {}

M.debug = false

local preamble = [[

#include <lua.h>
#include <lauxlib.h>
#include <stdio.h>
#include <stdlib.h>

#ifdef _WIN32
#include <windows.h>
#ifndef DLLAPI
#define DLLAPI __declspec(dllexport)
#endif
#else
#define DLLAPI
#endif

]]

-- Count number of lines in string.
local function numlines(s)
  return # s:gsub("[^\n]", "")
end

local function getPlatform()
    --- command capture
    function captureRedirectErr(cmd)
        local f = assert(io.popen(cmd .. ' 2>&1' , 'r'))
        local s = assert(f:read('*a'))
        f:close()
        s = string.gsub(s, '^%s+', '')
        s = string.gsub(s, '%s+$', '')
        s = string.gsub(s, '[\n\r]+', ' ')
        return s
    end
    local plf = captureRedirectErr('uname')
    if string.sub(plf,1,8) == "'uname' " then -- not found 'uname' cmd
        return 'Windows'
    else
        return plf -- 'Darwin', 'Linux'
    end
end

local myPlatform = getPlatform()

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
	local ret = handle:read('*a')
	handle:close()
	if (M.debug == true) then print(ret) end
	return ret
 end

local function getCompilerPath()
	if myPlatform == 'Windows' then
		-- Generate compiler bat
		local batfile = '@call "' .. os.getenv('VS120COMNTOOLS') .. '..\\..\\VC\\vcvarsall.bat" ' .. '\n'
		batfile = batfile .. '@cd ' .. os.getenv('TMP') .. '\n'
		batfile = batfile .. '@cl /nologo /EHsc /MD /O2 /D_WIN32=1 %1 %2 %3 %4 %5 %6 %7 %8 %9'
		local tempbat = make_temp_file(batfile, 'bat')
		return tempbat
		
	elseif myPlatform == 'Darwin' then
		return 'clang -O2'
	else
		return 'gcc -O2'
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

local function getLuaOption()
	if myPlatform == 'Windows' then
		return 'lua52.lib '
	else
		return '-llua '
	end
end

local function getIncludeOption()
	if myPlatform == 'Windows' then
		return '/I' .. luaIncludePathWin
	else
		return '-I' .. luaIncludePathMacLinux
	end
end

local function getLibraryOption()
	if myPlatform == 'Windows' then
		return '/LIBPATH:' .. luaLibraryPathWin
	else
		return '-L' .. luaLibraryPathMacLinux
	end
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
local function compile(src)
  local cpp = getCompilerPath()
  
  local incOption = getIncludeOption()
  local libOption = getLibraryOption()
  local CC = cpp .. ' ' .. incOption

  local pre_filename = make_preamble()
  src = ('#include %q\n'):format(pre_filename) .. src
  src = adjustlines(src, 2, 1)

  local dllExt = getDllExt()
  local modname = getTempFileName(dllExt)

  local srcname = make_temp_file(src, "c")
  local dlloption = getDllOption()
  local outoption = getOutOption()
  local luaoption = getLuaOption()
  local cmd = CC .. " " .. dlloption
        cmd = cmd .. " " .. srcname

  local lnkCmd = getLinkerOption() .. ' ' .. luaoption .. ' ' .. libOption .. ' ' .. outoption .. modname
  cmd = cmd .. " " .. lnkCmd
  exec(cmd)
	
  local func = assert(package.loadlib(modname, startFuncName))
  return func, modname
end
M.compile = compile

return M
