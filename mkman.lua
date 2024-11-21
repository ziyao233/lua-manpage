#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: MPL-2.0
--[[
--	mkman.lua
--	This script generates manpages for Lua C API from "Our Format" document
--	Copyright (c) 2024 Yao Zi.
--	Usage: ./mkman.lua <OUR_FORMAT_DOC> <OUTPUT_DIR>
--]]

local io		= require "io";
local string		= require "string";
local table		= require "table";
local math		= require "math";

local sections = {};
local src = assert(io.open(arg[1], 'r')):read('a');
local outDir = assert(arg[2]);

local format = string.format;
local function
addbuf(buf, s, ...)
	buf[#buf + 1] = format(s, ...);
end

local handleStyleSub;

local lListType;	-- Type of the list we're working with
			-- Could be "name-desc", "unordered" or nil
local seeAlsos;		-- Referred pages.

-- A pipe splits the name and the description.
local function
handleNameDescList(c)
	local name, desc = c:match("([^|]+)|(.+)");
	name = handleStyleSub(name);
	desc = handleStyleSub(desc);
	return ("\n.TP\n%s\n%s\n"):format(name, desc);
end
-- emulate unordered list with indentation and paragraph.
local function
handleUnorderedList(c)
	c = handleStyleSub(c);
	return "\n.P\n" .. c;
end
local function
handleExternalRef(c)
	return ("(see \n.I %s\nin Lua manual)"):format(c);
end
local styleTable = {
	-- TODO: id also means a reference
	id		= ".B",
	-- TODO: we should add defined IDs to NAME section
	defid		= ".B",
	Lid		= ".B",
	idx		= ".B",
	emph		= ".I",
	def		= ".I",
	Q		= ".I",
	x		= false,
	N		= false,
	T		= ".B",
	Char		= function(c)
				return ('\n' .. [[.B "'%s'"]] .. '\n'):
				       format(c);
			  end,
	-- A description is a name-description list
	description	= function(c)
				iListType = "name-desc";
				local res = handleStyleSub(c);
				iListType = nil;
				return res .. "\n.P\n";
			  end,
	-- itemize label creates an unordered list
	itemize		= function(c)
				iListType = "unordered";
				local res = handleStyleSub(c);
				iListType = nil;
				return "\n.RS\n" .. res .. "\n.RE\n.P\n";
			  end,
	-- items occur both in name-description and unordered lists
	item		= function(c)
				if iListType == "name-desc" then
					return handleNameDescList(c);
				elseif iListType == "unordered" then
					return handleUnorderedList(c);
				else
					assert(false,
					       "Item outside a list");
				end
			  end;
	see		= handleExternalRef,
	-- TODO: it's possible for seeF to refer a C-API, in this case it
	-- isn't an external reference
	seeF		= handleExternalRef,
	-- TODO: point out the precise manpage category
	seeC		= function(c)
				c = c:gsub('%s', '');
				seeAlsos[c] = true;	-- deduplicate
				return ("(see \n.BR %s(3) )\n"):format(c);
			  end,
};

local gsub = string.gsub;
local function
handleTag(src, tag, f)
	return gsub(src, ("@%s(%%b{})"):format(tag), function(content)
			content = content:sub(2, -2);
			return f(content) or "";
	end);
end

handleStyleSub = function(src)
	return gsub(src, "@(%a+)(%b{})", function(op, content)
			content = content:sub(2, -2);

			local replacement = styleTable[op];
			if not replacement and replacement ~= false then
				io.stderr:write(("%s is not handled!\n"):
						format(op));
				return content;
			elseif type(replacement) == "function" then
				return replacement(content);
			else
				content = handleStyleSub(content);
				return ("\n%s %s\n"):
				       format(replacement, content);
			end
	end);
end

local function
handleStyle(src)
	local verbatimList = {};
	--[[
	--	replace verbatim blocks with special marks and restore them
	--	later, preserving the format
	--]]
	src = gsub(src, "@verbatim(%b{})", function(t)
		local i = #verbatimList + 1;
		-- rep tags in a verbatim require no special handling
		verbatimList[i] = t:sub(2, -2):gsub("@rep(%b{})", function(c)
					return c:sub(2, -2);
				  end);
		return ("\1{%d}"):format(i);
	end);

	--[[
	--	strip the single newline, two consequent newlines are
	--	considered as a paragraph break
	--]]
	src = gsub(src, "%f[\n]\n", " ");
	src = gsub(src, "\n", "\n.P\n");

	return handleStyleSub(src):
	       -- handle entities like @nil @false @fail
	       gsub("@(%a+)", "\n.B %1\n"):
	       -- strip spaces at the start of line
	       gsub("\n%s+", "\n"):
	       -- avoid dots at start of the line being recognized as a command
	       gsub("\n(%.%s)", "\n.R %1"):
	       -- restore verbatim blocks
	       gsub("\1{(%d+)}", function(n)
	       		return ("\n.EX\n%s\n.EE\n"):
			       format(verbatimList[math.tointeger(n)]);
	       end):
	       -- a newline after a verbatim block may be left unstripped
	       gsub("(\n%.EE\n)%s+", "%1");
end

local errdesc = {
	['-'] = "This function never raises any error.",
	['m'] = "This function only raises out-of-memory error.",
	['v'] = "Errors that could be raised are described in DESCRIPTION.",
	['e'] = "This function can run arbitrary Lua code, any error could" ..
		" be raised.",
};

local function
readableStackUsage(s)
	return s:gsub('|', " or "):gsub("%?", "unknown");
end

local function
convert2man(src)
	-- A pipe character splits the prototype and the main description
	local prototype, desc = src:match("{([^|]+)|(.+)}");
	local stripped = assert(prototype:match("(.+);%s*$"));

	seeAlsos = {};

	local name, category;
	if stripped:match("typedef") then
		-- assuming it's a function pointer, we match the parentheses
		-- around the typename and the '*' following the left
		-- parenthese
		name = stripped:match("%(%s*%*%s*([%w_]+)");

		-- or it should be a struct or opaque type, the last token
		-- should be the name
		if not name then
			name = stripped:match("[%w_]+$");
		end
		category = "3type";
	else
		-- assuming a function, the name comes before the left
		-- parenthese which marks the start of argument list.
		-- Some functions in the manual are added extra parentheses
		-- around the name, we handle it with '%(*' and '%)*'
		name = stripped:match("%(*([%w_]+)%)*%s*%(");
		category = "3";
	end

	assert(name);

	prototype = prototype:gsub("@ldots", [[/* ... */]]);

	local buf = {};
	addbuf(buf, [[.TH %s %s "%s" "" "Lua C API"]],
		    name, category, os.date("%b %d, %Y"));

	addbuf(buf, ".SH NAME\n%s", name);

	addbuf(buf, ".SH SYNOPSIS");
	addbuf(buf, ".nf");
	addbuf(buf, ".B #include <%s>",
		    name:match("^luaL_") and "lauxlib.h" or "lua.h");
	addbuf(buf, ".P%s", ("\1" .. prototype):
			  gsub("[\1\n]+([^\n]+)", '\n.B "%1"'));
	addbuf(buf, ".fi");

	local apiiTag;
	desc = handleTag(desc, "apii", function(spec)
		local pops, pushes, err = spec:match("([^,]+),([^,]+),(.)");
		assert(pops and pushes and err);
		apiiTag = {
				pops	= readableStackUsage(pops),
				pushes	= readableStackUsage(pushes),
				err	= err,
			  };
		return "";
	end);
	if not apiiTag then
		io.stderr:write(("%s misses an apii tag\n"):format(name));
	end

	addbuf(buf, ".SH DESCRIPTION\n");
	buf[#buf + 1] = handleStyle(desc);

	--[[
	--	We generate two sections as specified by api indicator,
	--	"ERRORS" and "NOTES"
	--]]
	if apiiTag then
		addbuf(buf, ".SH ERRORS");
		addbuf(buf, ".P\n%s", assert(errdesc[apiiTag.err]));

		addbuf(buf, ".SH STACK USAGE");
		addbuf(buf, ".TP\n.B Push\n%s", apiiTag.pushes);
		addbuf(buf, ".TP\n.B Pop\n%s", apiiTag.pops);
	end

	if next(seeAlsos) then
		local refs = {};
		for ref, _ in pairs(seeAlsos) do
			table.insert(refs, ref);
		end
		table.sort(refs);

		addbuf(buf, ".SH SEE ALSO");
		-- TODO: cite precise category
		for i = 1, #refs - 1 do
			addbuf(buf, ".BR %s (3),", refs[i]);
		end
		addbuf(buf, ".BR %s (3)", refs[#refs]);
	end

	-- avoid missing newline at the end of file
	addbuf(buf, "");

	return name, category, table.concat(buf, '\n');
end

for src in src:gmatch("@APIEntry(%b{})") do
	local apiName, category, content = convert2man(src);
	local path = ("%s/%s.%s"):
		     format(outDir, apiName, category);
	print(("writing %s to %s"):format(apiName, path));

	assert(io.open(path, 'w')):write(content);
end
