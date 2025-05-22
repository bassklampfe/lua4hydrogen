#!/usr/bin/luajit
--[[
Copyright (c) 2025 bassklampfe

MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
--]]
pcall(require,"strict")
local sbyte=string.byte
local schar=string.char
local find=string.find
local strsub=string.sub

local sprintf=string.format
local push=table.insert
local join=table.concat

local function printf(...)
	io.write(sprintf(...))
	io.flush()
end

------------------------------------------------------------
-- configurable options
------------------------------------------------------------
local opt_drumkit=os.getenv("DRUMKIT") or "TimGM6mb"
local opt_quant_velocity=4
local opt_quant_tick=64
local opt_debug=false	-- create debug files

local st={['\n']='\\n',['\r']='\\r',['\t']='\\t',['\"']='\\"',['\\']='\\\\'}

------------------------------------------------------------
-- convert value (but not table) into readable string
-- @function vis
-- @tparam any val value to convert to string
-- @tparam[opt] int len if given, truncate long strings to given length
------------------------------------------------------------
local function vis(val,len)
	if type(val)~="string" then return tostring(val) end
	if len and #val>len then return vis(val:sub(1,len)).."..." end
	return '"'..(val:gsub("[\r\n\t\"\\]",st))..'"'
end

------------------------------------------------------------
-- convert value (also table) into readable string
-- @function vist
-- @tparam any val value to convert to string
------------------------------------------------------------
local function vist(val)
	local did={}
	local function vt(v)
		if type(v)~="table" then return vis(v) end
		if did[v] then return did[v] end
		did[v]=tostring(v)
		local r={}
		for kk,vv in pairs(v) do
			push(r,sprintf("[%s]=%s",vt(kk),vt(vv)))
		end
		return '{'..join(r,',\n')..'}'
	end
	return vt(val)
end


------------------------------------------------------------
-- check if a file exist
-- @function is_file
-- @tparam string path path of file to check
------------------------------------------------------------
local function is_file(path)
	local fd,err=io.open(path,"rb")
	if not fd then return nil,err end
	fd:close()
	return path
end


------------------------------------------------------------
-- load a file and return content
-- @function load_file
-- @tparam string path path of file to load from
-- @treturn string content of file
------------------------------------------------------------
local function load_file(path)
	local fd,err=io.open(path,"rb")
	if not fd then error(err) end
	local data=fd:read("*all")
	fd:close()
	return data
end

------------------------------------------------------------
-- save data to a file
-- @function save_file
-- @tparam string path path of file to save to
-- @tparam any ... values to write to file
------------------------------------------------------------
local function save_file(path,...)
	printf("save_file(%q)\n",path)
	local fd,err=io.open(path,"wb")
	if not fd then error(err) end
	fd:write(...)
	fd:close()
end

------------------------------------------------------------
-- round a value
-- @function lround
-- @tparam number flt value to round
-- @tparam[opt] number dig if given, round to multiple of
------------------------------------------------------------
local function lround(flt,dig)
	if dig then return lround(flt/dig)*dig end
	if flt<0 then return -lround(-flt) end
	return math.floor(flt+0.5)
end

------------------------------------------------------------
-- a simple lua to xml sequencer
--
-- this is really dumb and only works for specific table
-- @function data2xml
-- @tparam table data xml data, [1] is the tag
------------------------------------------------------------
local function data2xml(data)

	local function qxml(t)
		return t:gsub("[<>&;]",function(c) return sprintf("&#%d;",c:byte())end)
	end

	local function d2x(dat,ind)

		if dat==nil then return "" end
		assert(type(dat)=="table")
		local tag=dat[1]
		if #dat==1 then
			return sprintf("%s<%s/>",ind,tag)
		end
		if #dat==2 and type(dat[2])~="table" then
			return sprintf("%s<%s>%s</%s>",ind,tag,qxml(tostring(dat[2])),tag)
		else
			local xml={dat[0]}
			push(xml,sprintf("%s<%s>",ind,tag))
			for i=2,#dat do
				push(xml,d2x(dat[i],ind.." "))
			end
			push(xml,sprintf("%s</%s>",ind,tag))
			return join(xml,"\n")
		end
	end
	return d2x(data,"")
end


------------------------------------------------------------
-- a simple XML parser
--
-- this is my self contained xml parser, not so stupid
-- @function xml2data
-- @tparam string str string with xml data
-- @treturn {xml} datas parsed into a table
------------------------------------------------------------

------------------------------------------------------------
-- xml table with metafunctions
-- @table xml
------------------------------------------------------------

local function xml2data(str)
	local xml_mt={}
	xml_mt.__index=xml_mt

	------------------------------------------------------------
	-- @function xml:tag
	-- @treturn string tag of xml element
	------------------------------------------------------------

	function xml_mt:tag()
		return self[1]
	end
	------------------------------------------------------------
	-- @function xml:cdata
	-- @tparam[opt] string name if given return cdata of given element
	-- @treturn any value of string
	-- @error if name is given and element is not found, then returns error
	------------------------------------------------------------
	function xml_mt:cdata(name)
		if name then return assert(self:element(name)):cdata() end
		local cdata=self[2]
		if cdata and type(cdata)=="string" then return cdata end
		return nil,"no cdata in <"..self:tag()..">"
	end

	function xml_mt:element(name)
		for i=2,#self do
			local obj=self[i]
			if obj[1]==name then
				return obj,i
			end
		end
		return nil,"no element <"..tostring(name).."> in <"..self:tag()..">"
	end

	function xml_mt:elements()
		local n=1
		return function()
			n=n+1
			local elem=self[n]
			if elem then return elem,n end
		end
	end

	function xml_mt:attribute(name)
		local attr=self[name]
		if attr then return attr end
		return nil,"no attribute "..tostring(name).." in <"..self:tag()..">"
	end

	local qt={quot='"',apos='\'',lt='<',gt='>',amp='&'}
	local function unquote(s)
		return (s:gsub("&(%w+);",qt))
	end

	local pos=1
	-- helper for parse error
	local function fail(msg)
		error(msg.." at '"..(str:sub(pos,pos+60)).."'",2)
	end
	-- helper to iterate over attributes
	local function namval()
		local a,b,nam,val=find(str,'^%s+([%w:-]+)="([^"]+)"',pos)
		if a then pos=b+1 return nam,val end
	end
	-- luacheck: ignore 411 421
	local function need_obj()
		--
		-- skip comments
		--
		local a,b,comment=find(str,"^<!%-%-(.-)%-%->%s*",pos)
		while a do
			pos=b+1
			a,b,comment=find(str,"^<!%-%-(.-)%-%->%s*",pos)
		end
		--
		-- begin tag
		--
		local a,b,tag=find(str,'^<([%w_-]+)',pos)
		if not a then fail("expected '<tag'") end
		pos=b+1

		--
		-- attributes
		--
		local obj=setmetatable({tag},xml_mt)
		for nam,val in namval do obj[nam]=unquote(val) end

		--
		-- quick end-of-tag
		--
		local a,b=find(str,'^%s*/>%s*',pos)
		if a then
			pos=b+1
			return obj
		end

		--
		-- end-of tag
		--
		local a,b=find(str,'^>%s*',pos)
		if not a then fail("expected '>'") end
		pos=b+1

		--
		-- any elements?
		--
		while not find(str,"^</",pos) do
			if find(str,'^<',pos) then
				push(obj,need_obj())
			else
				local a,b,cdata=find(str,"^([^<]+)%s*<",pos)
				if not a then fail("Expected literal") end
				pos=b+1-1 -- exclude '<'
				push(obj,unquote(cdata))
			end
		end

		--
		-- closing tag
		--
		local a,b,etag=find(str,'^</([%w_-]+)>%s*',pos)
		if not a then fail("expected end-of-tag "..tostring(tag)) end
		if etag~=tag then fail("tag mismatch "..vis(tag).." vs "..vis(etag))end
		pos=b+1
		return obj
	end

	--
	-- check for document prolog (ignored for svn)
	--
	local xmlobj
	local a,b,xmltag=find(str,"<(%?%w+)",pos)
	if a then
		pos=b+1
		xmlobj={xmltag}
		for nam,val in namval do xmlobj[nam]=val end
		local a,b=find(str,'^%?>%s*',pos)
		if not a then fail("expected '?>'") end
		pos=b+1
	end

	--
	-- get the one and only top object in xml
	--
	local obj=need_obj()
	obj[0]=xmlobj

	--
	-- check
	--
	if pos<=#str then
		fail("expected no more data")
	end
	return obj
end

----------------------------------------
-- reading a midi file
----------------------------------------
local function read_midi(midi_path)

	local function Error(...)
		local _,result=pcall(sprintf,...)
		error(result,2)
	end


	local bh={} for b=0,255 do bh[schar(b)]=sprintf("%02X",b)end
	local function hex(s) return s:gsub(".",bh) end

	local function one_byte(data) return {b1=sbyte(data,1)} end

	--------------------------------------------
	-- table of known meta events
	--------------------------------------------
	local meta_events=
	{
		[0x00]={type='sequence_number',len=1,code=one_byte },
		[0x20]={type='channel_prefix' ,len=1,code=one_byte },
		[0x21]={type='port_prefix'    ,len=1,code=one_byte },
		[0x2F]={type='eof'            ,len=0,code=function() return {} end },
		[0x51]={type='set_tempo'      ,len=3,code=function(data) return {tempo=(sbyte(data,1)*256+sbyte(data,2))*256+sbyte(data,3)}end },
		[0x58]={type='time_signature' ,len=4,code=function(data) return {b1=sbyte(data,1),b2=sbyte(data,2),b3=sbyte(data,3),b4=sbyte(data,4)} end },
		[0x59]={type='key_signature'  ,len=2,code=function(data) return {b1=sbyte(data,1),b2=sbyte(data,2)} end },
		[0x54]={type='smpte_offset'   ,len=5,code=function(data) return	{value=(((sbyte(data,1)*256+sbyte(data,2))*256+sbyte(data,3))*256+sbyte(data,4))*256+sbyte(data,5)} 	end },
		[0x7F]={type='sequencer_specific',code=function(data) return	{data=hex(data)} 	end },
	}

	--------------------------------------------
	-- table of known text events
	--------------------------------------------
	local text_events=
	{
		[0x01]='text_event',
		[0x02]='copyright_text_event',
		[0x03]='track_name',
		[0x04]='instrument_name',
		[0x05]='lyric',
		[0x06]='marker',
		[0x07]='cue_point',
		[0x08]='text_event_08',
		[0x09]='text_event_09',
		[0x0a]='text_event_0a',
		[0x0b]='text_event_0b',
		[0x0c]='text_event_0c',
		[0x0d]='text_event_0d',
		[0x0e]='text_event_0e',
		[0x0f]='text_event_0f',
	}

	------------------------------------------------------------
	-- table of known channel events
	------------------------------------------------------------
	local channel_events=
	{
		[0x80]={type='note_off'           ,len=2,code=function(data) return {pitch=sbyte(data,1),velo=sbyte(data,2)} end },
		[0x90]={type='note_on'            ,len=2,code=function(data) return {pitch=sbyte(data,1),velo=sbyte(data,2)} end },
		[0xA0]={type='key_aftertouch'     ,len=2,code=function(data) return {pitch=sbyte(data,1),velo=sbyte(data,2)} end },
		[0xB0]={type='control_change'     ,len=2,code=function(data) return {ctrl=sbyte(data,1),val=sbyte(data,2)} end },
		[0xC0]={type='patch_change'       ,len=1,code=function(data) return {patch=sbyte(data,1)} end },
		[0xD0]={type='channel_after_touch',len=1,code=function(data) return {velo=sbyte(data,1)} end },
		[0xE0]={type='pitch_wheel_change' ,len=2,code=function(data) return {pitch=(sbyte(data,1)+sbyte(data,2)*128)-0x2000} end },
	}

	------------------------------------------------------------------------
	--- convert a mtrk into array of events
	--- @param mtrk : binary data of track
	--- @return (byref) array of event-arrays
	------------------------------------------------------------------------
	local function mtrk_2_events(mtrk)
		local curr_cmd
		local events={}		-- return value
		local curr_tick=0;	-- time tick
		local pos=1
		local mtrk_size=#mtrk
		local byte

		local function vlen()
			local b=sbyte(mtrk,pos) or error"short data in mtrk"
			pos=pos+1
			local v=b
			while b>=0x80 do
				b=sbyte(mtrk,pos) or error"short data in mtrk"
				pos=pos+1
				v=(v-128)*128+b
			end
			return v
		end

		--
		-- parse the data
		--
		while pos<=mtrk_size do
			--
			-- get the duration
			--
			local dura=vlen()
			--
			-- update curr_tick if requested
			--
			curr_tick=curr_tick+dura
			--
			-- get the possible command byte
			--
			byte=sbyte(mtrk,pos) or error"short data in mtrk"
			--
			-- meta-events (have no running status!)
			--
			if byte>=0xF0 then
				local type=byte
				pos=pos+1
				-- Meta Events have the general form:
				-- FF <type> <length> <data>
				if type==0xFF then
					type=sbyte(mtrk,pos) or error"short data in mtrk"
					pos=pos+1
					--
					-- meta-events have var_len
					--
					local size=vlen()
					if pos+size>mtrk_size+1 then Error("Meta event pos=%d,size=%d beyond mtrk size=%d",pos,size,mtrk_size) end
					local data=strsub(mtrk,pos,pos+size-1) pos=pos+size
					--
					-- try known text event
					--
					if text_events[type] then
						local text_info=text_events[type]
						events[#events+1]={curr_tick,text_info,data=data}
						--
						-- try known meta event
						--
					elseif meta_events[type] then
						local meta_info=meta_events[type]
						if meta_info.len and meta_info.len~=size then Error("event size mismatch have=%d want=%d",size,meta_info.len) end
						local meta_data=meta_info.code(data)
						meta_data[1]=curr_tick
						meta_data[2]=meta_info.type
						events[#events+1]=meta_data
						if type==0x2F then break end	-- eof
						--
						-- unknown meta event
						--
					else
						events[#events+1]={curr_tick,"raw_meta_event",numb=type,data=data}
					end
					--
					-- F0 <length> <sysex_data>  F0 Sysex Event
					--
				elseif type==0xF0 or type==0xF7 then
					--
					-- sysex have var_len
					--
					local size=vlen()
					if pos+size>mtrk_size+1 then Error("Sysex event pos=%d,size=%d beyond mtrk size=%d",pos,size,mtrk_size) end
					local data=strsub(mtrk,pos,pos+size-1) pos=pos+size;
					events[#events+1]={curr_tick,"sysex",byte=type,data=hex(data)}
				else
					--
					-- TODO: F1..FE
					--
					Error("pos %04X:unknown meta %02X",pos,type)
				end

			else
				--
				-- get running status
				--
				if byte>=0x80 then
					curr_cmd=byte
					pos=pos+1
				end
				local chan=curr_cmd%16
				local type=curr_cmd-chan
				chan=chan+1
				local event_info=assert(channel_events[type])
				local size=event_info.len
				local data=strsub(mtrk,pos,pos+size-1)
				pos=pos+size
				data=event_info.code(data)
				data[1]=curr_tick
				data[2]=event_info.type
				data.chan=chan
				events[#events+1]=data
			end
		end
		return events
	end


	local function decode_midi(Read)
		local function stohl(s)
			local a,b,c,d=sbyte(s,1,4)
			return ((a*256+b)*256+c)*256+d
		end
		local function stohs(s)
			local a,b=sbyte(s,1,2)
			return a*256+b
		end

		local function ReadChunk(want_type,want_size)
			local head=Read(8)
			assert(#head==8,"head len<>8")
			local have_type,have_size=head:sub(1,4),head:sub(5,8) -- missing unpack N
			assert(#have_type==4,"have_type len<>4")
			assert(#have_size==4,"have_size len<>4")
			have_size=stohl(have_size)
			if have_type~=want_type then Error("Bad chunk type want %q have %q",want_type,have_type) end
			if want_size and have_size~=want_size then Error("Bad chunk size want %d have %d",want_size,have_size) end
			local data=Read(have_size) or Error"read failed"
			if #data~=have_size then Error("Short read want=%d have=%d",have_size,#data) end
			return data
		end

		local data=ReadChunk('MThd',6);
		local frmt,trks,tick=stohs(data:sub(1,2)),stohs(data:sub(3,4)),stohs(data:sub(5,6))
		local tracks={}
		local midi={frmt=frmt,trks=trks,tick=tick,tracks=tracks}
		for t=1,trks do
			local chunkdata=ReadChunk('MTrk');
			local events=mtrk_2_events(chunkdata);
			tracks[t]=events
		end
		return midi
	end


	local midi_fd=assert(io.open(midi_path,"rb"))
	local function Read(n) return midi_fd:read(n) or Error("read(%s)failed",midi_path) end
	local midi=decode_midi(Read)
	midi_fd:close()
	return midi
end

--
-- READ THE DRUMKIT
--
--~ local known_drumkits=
--~ {
--~ 	["ForzeeStereo"]={35,37,38,39,40,41,42,44,45,46,47,48,49,50,51,52,53,54,55,56,57,59,67,68,80,81},
--~ 	["TR808EmulationKit"]={35,36,38,39,40,42,43,44,45,46,48,49,56,63,70,75},
--~ 	["GMRockKit"]={36,37,38,39,40,41,42,43,44,45,46,49,51,56,57,59,81,82},
--~ 	["Roland_CR79Kit"]={35,36,37,38,39,40,42,43,44,45,46,47,49,50,51,52,54,55,56,57,60,62,63,64,67,68,73,74,75,76,79},
--~ }


--============================================================
-- processing the drumkit, searching for midi pitches
--============================================================

--local drumkit_path="/usr/share/hydrogen/data/drumkits/TR808EmulationKit"
--local drumkit_path="/usr/share/hydrogen/data/drumkits/ForzeeStereo"
--local drumkit_path="/usr/share/hydrogen/data/drumkits/TR808EmulationKit"

local HOME=os.getenv("HOME")
local drumkit_path=is_file("/usr/share/hydrogen/data/drumkits/"..opt_drumkit.."/drumkit.xml")
or (HOME and is_file(HOME.."/.hydrogen/data/drumkits/"..opt_drumkit.."/drumkit.xml"))
or error("No drumkit "..opt_drumkit)
local drumkitPath=drumkit_path:match("(.*)/")
local drumkit=load_file(drumkit_path)
local drumkit_data=assert(xml2data(drumkit))

--
-- extract the name
--
local drumkit_name=drumkit_data:cdata("name")
local componentList=drumkit_data:element("componentList")
--
-- extract the instrumentlist
--
local instrumentList=drumkit_data:element("instrumentList") or error("no instrumentList in "..drumkit_path)
-- insert name else wont find samples
for instrument in instrumentList:elements() do
	local _,idx=instrument:element("name")
	push(instrument,idx+1,{"drumkit",drumkit_name})
	push(instrument,idx+1,{"drumkitPath",drumkitPath})
end
--instrumentlist=instrumentlist:gsub("</name>\n%s+<volume>","</name>\n   <drumkit>"..drumkit_name.."</drumkit>\n  <volume>")

--
-- create translation table
--
local PITCH_METRONOME_BELL=34
local PITCH_ACOUSTIC_BASS_DRUM=35
local PITCH_BASS_DRUM_1=36
--~ local PITCH_SIDE_STICK=37
local PITCH_ACOUSTIC_SNARE=38
local PITCH_HAND_CLAP=39
local PITCH_ELECTRIC_SNARE=40
--~ local PITCH_LOW_FLOOR_TOM=41
--~ local PITCH_CLOSED_HIHAT=42
--~ local PITCH_HIGH_FLOOR_TOM=43
--~ local PITCH_PEDAL_HIHAT=44
local PITCH_LOW_TOM=45
--~ local PITCH_OPEN_HIHAT=46
--~ local PITCH_LOW_MID_TOM=47
--~ local PITCH_HI_MID_TOM=48
local PITCH_CRASH_CYMBAL_1=49
local PITCH_HIGH_TOM=50
local PITCH_RIDE_CYMBAL_1=51
--~ local PITCH_CHINESE_CYMBAL=52
local PITCH_RIDE_BELL=53
local PITCH_TAMBOURINE=54
local PITCH_SPLASH_CYMBAL=55
--~ local PITCH_COWBELL=56
local PITCH_CRASH_CYMBAL_2=57
--~ local PITCH_VIBRASLAP=58
local PITCH_RIDE_CYMBAL_2=59
--~ local PITCH_HI_BONGO=60
--~ local PITCH_LOW_BONGO=61
--~ local PITCH_MUTE_HI_CONGA=62
--~ local PITCH_OPEN_HI_CONGA=63
--~ local PITCH_LOW_CONGA=64
local PITCH_HIGH_TIMBALE=65
--~ local PITCH_LOW_TIMBALE=66
--~ local PITCH_HIGH_AGOGO=67
--~ local PITCH_LOW_AGOGO=68
--~ local PITCH_CABASA=69
--~ local PITCH_MARACAS=70
--~ local PITCH_SHORT_WHISTLE=71
--~ local PITCH_LONG_WHISTLE=72
--local PITCH_SHORT_GUIRO=73
--local PITCH_LONG_GUIRO=74
--local PITCH_CLAVES=75
local PITCH_HI_WOOD_BLOCK=76
--local PITCH_LOW_WOOD_BLOCK=77
--local PITCH_MUTE_CUICA=78
--local PITCH_OPEN_CUICA=79
--local PITCH_MUTE_TRIANGLE=80
--local PITCH_OPEN_TRIANGLE=81
--local PITCH_SHAKER=82
local PITCH_SLEIGH_BELL=83
local PITCH_CASTANETS=85


local pitch2instrument={}
local unknown_midis={}
local midi_stat={}
-- https://www.zendrum.com/resource-site/drumnotes.htm
--~ local similarInstruments =
--~ {
--~ 	[86]=36,	-- stomp -> basss drum
--~ 	[31]=38,	-- Side Stick
--~ 	[36]=35, 	-- Acoustic Bass Drum > Bass Drum 1
--~ 	[40]=38,	-- Acoustic Snare > Electric Snare
--~ 	[41]=43,	-- High Floor Tom > Low Floor Tom
--~ 	[45]=47,	-- LOW_Mid Tom > Low Tom
--~ 	[52]=59,	-- Ride Cymbal 2 > Chinese Cymbal
--~ 	[53]=59,	-- Ride Cymbal 2 > Ride Bell
--~ 	[55]=49,	-- Crash Cymbal 1 > Splash Cymbal
--~ 	[57]=49,	-- Crash Cymbal 1 > Splash Cymbal
--~ 	--[39]=54,	-- Tambourine > Hand Clap
--~ }

--~ local similarInstruments =
--~ {
--~ 	[31]=38,	-- Side Stick
--~ 	[36]=35, 	-- Acoustic Bass Drum > Bass Drum 1
--~ 	[40]=38,	-- Acoustic Snare > Electric Snare
--~ 	[41]=43,	-- High Floor Tom > Low Floor Tom
--~ 	[45]=47,	-- Low-Mid Tom > Low Tom
--~ 	[52]=59,	-- Ride Cymbal 2 > Chinese Cymbal
--~ 	[53]=59,	-- Ride Cymbal 2 > Ride Bell
--~ 	[55]=49,	-- Crash Cymbal 1 > Splash Cymbal
--~ 	[57]=49,	-- Crash Cymbal 1 > Splash Cymbal
--~ 	[39]=54,	-- Tambourine > Hand Clap
--~ }
local midiReplacements={}
--for k,v in pairs(similarInstruments) do
--	midiReplacements[k]=v
--	midiReplacements[v]=k
--end
local best_replacements=
{
	{PITCH_HAND_CLAP,PITCH_TAMBOURINE},
	{PITCH_SPLASH_CYMBAL,PITCH_CRASH_CYMBAL_1,PITCH_CRASH_CYMBAL_2},
	{PITCH_RIDE_BELL,PITCH_RIDE_CYMBAL_1,PITCH_RIDE_CYMBAL_2,PITCH_SLEIGH_BELL},
	{PITCH_ACOUSTIC_BASS_DRUM,PITCH_BASS_DRUM_1},
	{PITCH_CASTANETS,PITCH_HI_WOOD_BLOCK,PITCH_HIGH_TIMBALE,PITCH_HIGH_TOM,PITCH_LOW_TOM},
	{PITCH_ACOUSTIC_SNARE,PITCH_ELECTRIC_SNARE},
	{PITCH_METRONOME_BELL,PITCH_RIDE_BELL,PITCH_RIDE_CYMBAL_1,PITCH_RIDE_CYMBAL_2},
}
--
-- read all the midiOutNote from drumkit
--
for instrument in instrumentList:elements("instrument") do
	local id=instrument:cdata("id")or error("no id in instrument")
	local name=instrument:cdata("name") or error("no name in instrument")
	local midiOutNote=instrument:cdata("midiOutNote")
	local nameMidiOutNote=name:match("^(%d+)")
	if midiOutNote=="60" and nameMidiOutNote then
		midiOutNote=nameMidiOutNote
	end
	if id and midiOutNote then
		id=assert(tonumber(id))
		midiOutNote=assert(tonumber(midiOutNote))
		--printf("id=%s midiOutNote=%s\n",id,midiOutNote)
		pitch2instrument[midiOutNote]=id
		midiReplacements[midiOutNote]=nil
	end
end

for _,replacement in ipairs(best_replacements) do
	local function any_pitch_unknown()
		for _,pitch in ipairs(replacement) do
			if not pitch2instrument[pitch] and not midiReplacements[pitch] then
				return pitch
			end
		end
	end

	local function find_best_pitch()
		for _,pitch in ipairs(replacement) do
			if pitch2instrument[pitch] then
				return pitch
			end
		end
	end
	if any_pitch_unknown() then
		local best_pitch=find_best_pitch()
		printf("best pitch for %s is %s\n",join(replacement,','),tostring(best_pitch))
		if best_pitch then
			for _,pitch in ipairs(replacement) do
				if not pitch2instrument[pitch] and not midiReplacements[pitch] then
					midiReplacements[pitch]=best_pitch
				end
			end
		end
	end
end

--os.exit()

--
-- we need a stable sort, table.sort() is NOT stable
--
local function insertsort(t,f)
	for i=2,#t do
		local v=t[i]
		local j=i-1
		while j>=1 and f(v,t[j]) do
			t[j+1]=t[j]
			j=j-1
		end
		t[j+1]=v
	end
end

--
-- filter events relevant for hydrogen out of midi
--
local function filter_midi_events(midi_data)

	--Midi drum channel
	local drumChannel=10
	local hydrogen_events={}
	local count_drum_events=0
	--
	-- STEP 1:
	-- process the midi file read in
	-- filter relevant events
	--
	local signaturea,signatureb=4,4
	local f_tick=(midi_data.tick*4)*(signaturea/signatureb)/opt_quant_tick

	local f_velo=(127/opt_quant_velocity);
	for _,midi_track in ipairs(midi_data.tracks) do
		for _,midi_event in ipairs(midi_track) do
			local t,e=unpack(midi_event)
			if e=="note_on" and midi_event.chan==drumChannel and midi_event.velo>0 then
				local pitch=assert(midi_event.pitch,"no pitch in event")
				midi_stat[pitch]=(midi_stat[pitch] or 0)+1
				pitch=midiReplacements[pitch] or pitch
				local instrument=pitch2instrument[pitch]
				if instrument then
					local velo=lround(midi_event.velo/f_velo)*f_velo
					local tick=lround(t/f_tick)*f_tick

					push(hydrogen_events,{t=tick,instrument=instrument,velo=velo})
					count_drum_events=count_drum_events+1
				else
					unknown_midis[pitch]=(unknown_midis[pitch] or 0)+1
				end
			end
			if e=="set_tempo" then
				local bpm=lround(60*(1000000/midi_event.tempo),0.01)
				--printf("%s:tempo(%s)\n",t,bpm)
				push(hydrogen_events,{t=t,bpm=bpm})
			end
			if e=="time_signature" then
				local a=midi_event.b1
				local b=math.ldexp(1,midi_event.b2)
				--printf("%s:time_signature(%s,%s){%s,%s,%s,%s}\n",t,a,b,event.b1,event.b2,event.b3,event.b4)
				push(hydrogen_events,{t=t,a=a,b=b})
				signaturea,signatureb=a,b
				f_tick=(midi_data.tick*4)*(signaturea/signatureb)/opt_quant_tick
			end
		end
	end
	if count_drum_events>0 then
		-- sort by time
		insertsort(hydrogen_events,function(a,b)return a.t<b.t end)
		return hydrogen_events
	end
end


local function get_sequence_magic(bar)
	local sequenceMagic={}
	for _,event in ipairs(bar) do
		local t,i,v=unpack(event)
		push(sequenceMagic,t..":"..i..":"..v)
	end
	table.sort(sequenceMagic)
	return bar.a.."/"..bar.b..":"..join(sequenceMagic,",")
end

local used_instruments={}

local function sequenceList_to_noteList(bar)
	local noteList={"noteList"}
	for _,event in ipairs(bar) do
		local position,instrument,velocity=unpack(event)
		used_instruments[instrument]=(used_instruments[instrument] or 0)+1
		push(noteList,
			{"note",
				{"position",position},
				{"leadlag",0},
				{"velocity",lround(velocity/128.0,0.01)},
				{"pan",0},
				{"pitch",0},
				{"key","C0"},
				{"length",-1},
				{"instrument",instrument},
				{"note_off",false},
				{"probability",1},
			})
	end
	return noteList
end

local function midi_to_hydrogen(midi_file)


	local PATTERNLENGTH=192
	--
	-- read the midi file
	--
	local midi_data=read_midi(midi_file,1)
	local midi_name=midi_file:gsub(".*/","")

	--
	-- filter relevant events
	--
	local hydrogen_events=filter_midi_events(midi_data)
	if not hydrogen_events then
		error("no drum events in "..midi_file,0)
	end
	--
	-- sort into bars and a timeline
	--
	local BPMTimeLine={"BPMTimeLine"}
	local bar_bpm={}
	local song_bpm
	local signaturea,signatureb=4,4
	local function get_barlength()return (midi_data.tick*4)*(signaturea/signatureb) end
	local barlength=get_barlength()
	local barnumber=1
	local barbegin=0
	local barend=barbegin+barlength
	local newbar={a=signaturea,b=signaturea}
	local bars={newbar}
	for _,event in ipairs(hydrogen_events) do
		local t=event.t
		while t>=barend do
			barnumber=barnumber+1
			newbar={a=signaturea,b=signatureb}
			push(bars,newbar)
			barbegin=barend
			barend=barbegin+barlength
			--printf("bar[%d]=%d:%d\n",barnumber,barbegin,barend)
		end

		if event.bpm then
			song_bpm=song_bpm or event.bpm
			local newBPM=bar_bpm[barnumber]
			if newBPM then
				newBPM[3][2]=event.bpm
			else
				newBPM={"newBPM",{"BAR",barnumber-1},{"BPM",event.bpm}}
				bar_bpm[barnumber]=newBPM
				push(BPMTimeLine,newBPM)
			end
		end
		if event.a then
			signaturea,signatureb=event.a,event.b
			newbar.a,newbar.b=signaturea,signatureb
			barlength=get_barlength()
			--printf("a=%s b=%s barlengh=%s\n",newbar.a,newbar.b,barlength)
			barend=barbegin+barlength
			--printf("bar[%d]=%d:%d\n",barnumber,barbegin,barend)
		end

		if event.instrument then
			local ht=lround((t-barbegin)*PATTERNLENGTH/(midi_data.tick*4))--*(newbar.a/newbar.b))
			--printf("t=%s\n",ht)
			push(newbar,{ht,event.instrument,event.velo})
		end
	end

	local sequencePatternMap={}
	local patternSequence={"patternSequence"}
	local patternList={"patternList"}
	local virtualPatternList={"virtualPatternList"}
	for _,bar in ipairs(bars) do
		if #bar>0 then
			local sequenceMagic=get_sequence_magic(bar)
			local patternID=sequencePatternMap[sequenceMagic]
			if not patternID then
				patternID=#patternList
				sequencePatternMap[sequenceMagic]=patternID
				local noteList=sequenceList_to_noteList(bar)
				push(patternList,
					{"pattern",
						{"name",patternID},
						{"info",""},
						{"category","unknown"},
						{"size",PATTERNLENGTH*bar.a/bar.b},
						{"denominator",bar.b},
						noteList,
					})

			end
			push(patternSequence,{"group",{"patternID",patternID}})
		else
			push(patternSequence,{"group"})
		end
	end

	local idx=2
	while idx<=#instrumentList do
		local instrument=instrumentList[idx]
		local id=instrument:cdata("id")or error("no id in instrument")
		id=assert(tonumber(id))
		if used_instruments[id] then
			idx=idx+1
		else
			table.remove(instrumentList,idx)
		end
	end

	local song=
	{
		[0]='<?xml version="1.0" encoding="UTF-8"?>',
		"song",
		{"version","1.2.4"},
		{"bpm",song_bpm or 120},
		{"volume",0.5},
		{"isMuted",false},
		{"metronomeVolume",0.5},
		{"name","Untitled Song"},
		{"author","Unknown Author"},
		{"notes","created from "..midi_name},
		{"license","undefined license"},
		{"loopEnabled",false},
		{"patternModeMode",true},
		{"playbackTrackFilename",""},
		{"playbackTrackEnabled",false},
		{"playbackTrackVolume",0},
		{"action_mode",0},
		{"isPatternEditorLocked",true},
		{"mode","song"},
		{"pan_law_type","RATIO_STRAIGHT_POLYGONAL"},
		{"pan_law_k_norm",1.33333},
		{"humanize_time",0},
		{"humanize_velocity",0},
		{"swing_factor",0},

		componentList,
		instrumentList,
		patternList,
		virtualPatternList,
		patternSequence,
		{"ladspa"},
		BPMTimeLine,
		{"timeLineTag"},
	}
	local xml=data2xml(song)
	return xml,song
end

_G.midi_to_hydrogen=midi_to_hydrogen

--
-- called from commandline ?
--
if rawget(_G,"arg") then
	local in_file=arg[1] or error("no infile given")
	local out_file=arg[2]
	if not out_file then out_file=in_file:gsub("%.%w+$","")..".h2song" end
	local hydrogen_h2song=midi_to_hydrogen(in_file)
	save_file(out_file,hydrogen_h2song)
	save_file(out_file.."-base",hydrogen_h2song)
	print "Done !"
end
