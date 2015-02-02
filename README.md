# InlineC.lua

Inline C Library at Lua

##Usage

    local CC = require "inlinec"
    local f = CC.compile [[
    DLLAPI int start(lua_State * L) {
      puts("Hello from C");
      return 0;
    }
    ]]
    f();
    
    -----------
    Output:
    
    Hello from C

## Environment

* OSX + Xcode (with Command line tools)
* Windows + VisualStudio 2013
* Linux + gcc


## Original Idea and base code

   (c) D.Manura, 2008.
   Licensed under the same terms as Lua itself (MIT license).
   
   http://lua-users.org/wiki/InlineCee


## Lisence

   (c) Kentaro Oku
   Licensed under the same terms as Lua itself (MIT license).

