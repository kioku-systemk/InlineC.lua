local CC = require "inlinec"
CC.debug = true

local f;
local modname
f, modname = CC.compile [[
  DLLAPI int start(lua_State * L) {
    luaL_checkstring(L,1);
	lua_pushstring(L, "hello ");
    lua_pushvalue(L, 1);
    lua_concat(L, 2);
	for (int i = 0; i < 10; i++){
		lua_pushinteger(L, i);	
		lua_concat(L, 2);
	}
    return 1;
  }
]]

print(modname)
print(f("world"))  --> "hello world0123456789"