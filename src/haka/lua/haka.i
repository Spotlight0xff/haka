/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

%module haka

%{
#include <stdint.h>
#include <wchar.h>

#include "app.h"
#include "lua/state.h"
#include <haka/packet_module.h>
#include <haka/thread.h>
#include <haka/module.h>
#include <haka/alert.h>
#include <haka/config.h>

char *module_prefix = HAKA_MODULE_PREFIX;
char *module_suffix = HAKA_MODULE_SUFFIX;

%}

%include "haka/lua/swig.si"

%nodefaultctor;
%nodefaultdtor;

%rename(current_thread) thread_getid;
int thread_getid();

%rename(module_path) module_get_path;
const char *module_get_path();

%immutable;
char *module_prefix;
char *module_suffix;

struct time {
	int    secs;
	int    nsecs;

	%extend {
		time(double ts) {
			struct time *t = malloc(sizeof(struct time));
			if (!t) {
				error(L"memory error");
				return NULL;
			}

			time_build(t, ts);
			return t;
		}

		~time() {
			free($self);
		}

		%immutable;
		double seconds;

		temporary_string __tostring()
		{
			char *ret = malloc(TIME_BUFSIZE);
			if (!ret) {
				error(L"memory error");
				return NULL;
			}

			if (!time_tostring($self, ret, TIME_BUFSIZE)) {
				assert(check_error());
				free(ret);
				return NULL;
			}

			return ret;
		}
	}
};

STRUCT_UNKNOWN_KEY_ERROR(time);

%{

double time_seconds_get(struct time *t) {
	return time_sec(t);
}

%}

%native(_getswigclassmetatable) int _getswigclassmetatable(struct lua_State *L);

%{
int _getswigclassmetatable(struct lua_State *L)
{
	SWIG_Lua_get_class_registry(L);
	return 1;
}
%}

%luacode {
	haka = unpack({...})

	function string.split(str, delim)
		local ret = {}
		local last_end = 1
		local s, e = str:find(delim, 1)

		while s do
			cap = str:sub(last_end, e-1)
			table.insert(ret, cap)

			last_end = e+1
			s, e = str:find(delim, last_end)
		end

		if last_end <= #str then
			cap = str:sub(last_end)
			table.insert(ret, cap)
		end

		return ret
	end

	local function addpath(dst, paths, exts)
		local pathtable = string.split(dst, ';')

		for _, path in pairs(string.split(paths, ';')) do
			for _, ext in pairs(exts) do
				local p = string.gsub(path, '*', ext)
				table.insert(pathtable, p)
			end
		end

		return table.concat(pathtable, ';')
	end

	haka._on_exit = {}

	function haka._exiting()
		for k, f in pairs(haka._on_exit) do
			haka._on_exit[k] = nil
			f()
		end
	end

	function haka.on_exit(func)
		table.insert(haka._on_exit, func)
	end

	package.cpath = addpath(package.cpath, haka.module_path(), { haka.module_prefix .. '?' .. haka.module_suffix })
	package.path = addpath(package.path, haka.module_path(), { '?.bc', '?.lua' })

	swig = {}
	function swig.getclassmetatable(name)
		local ret = haka._getswigclassmetatable()[name]
		assert(ret, string.format("unknown swig class '%s'", name))
		return ret
	end

	function haka.pcall(func, ...)
		assert(func)
		local args = {...}
		local ret, msg = xpcall(function () func(unpack(args)) end, debug.format_error)
		if not ret then
			haka.log.error("core", msg)
			return false
		else
			return true
		end
	end

	require('class')
	require('utils')

	function haka.initialize()
		require('events')
		require('context')
		require('rule')
		require('rule_group')
		require('dissector')
		require('grammar')
	end
}

%include "lua/vbuffer.i"
