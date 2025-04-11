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

require"strict"
local lfs=require"lfs"
-- luacheck: globals vis vist save_data save_file ShowData

local sprintf=string.format
local schar=string.char
local push=table.insert
local join=table.concat
local function printf(...)
	io.write(sprintf(...))
end

local function save_file(path,...)
	local fd=assert(io.open(path,"wb"))
	fd:write(...)
	fd:close()
end

local function Error(...)
	local _,msg=pcall(sprintf,...)
	error(msg,2)
end

local function hex(bytes)
	return bytes:gsub(".",function(c)return sprintf("%02X",c:byte())end)
end


local function read_soundfont(sf_file)
	printf("read_soundfont(%q)\n",sf_file)
	local fd=assert(io.open(sf_file,"rb"))

	local function get_id()
		return fd:read(4)
	end

	local function get_long()
		local bytes=fd:read(4)
		local a,b,c,d=bytes:byte(1,4)
		return ((d*256+c)*256+b)*256+a
	end

	local function pos()
		return fd:seek()
	end

	local function get_byte()
		local bytes=fd:read(1)
		local a=bytes:byte(1)
		return a
	end

	local function get_word()
		local bytes=fd:read(2)
		local a,b=bytes:byte(1,2)
		return b*256+a
	end

	local function get_name(len)
		return fd:read(len):gsub("%z.*$",""):gsub("%s+$","")
	end

	local function Expect(want,have)
		if want~=have then
			Error("Expect(want=%s have=%s)failed\n",vis(want),vis(have))
		end
	end

	local function genAmountType()
		return get_word()
	end

	local function SFGenerator()
		return get_word()
	end

	local function SFSampleLink()
		local w=get_word()
		if w==1 then return "Mono Sample" end
		return w
	end

	-- 8.2 Modulator Source Enumerators
	local function sfModulator()
		local word=get_word()
		-- use trivial math to avoid luabit dependency
		local function get_bits(mask) local div=mask+1 local val=word%div word=(word-val)/div return val end
		local Index=get_bits(0x7F)	-- A 7 bit value specifying the controller source
		local CC=get_bits(1) --  MIDI Continuous Controller Flag
		local Direction=get_bits(1) -- Direction
		local Polarity=get_bits(1) -- Polarity
		local Type=word -- A 6 bit value specifying the continuity of the controller
		return {Type=Type,Polarity=Polarity,Direction=Direction,CC=CC,Index=Index}
	end

	local function SFTransform()
		return get_word()
	end

	local rec_func={}

	--[[
	struct sfVersionTag
	{
		WORD wMajor;
		WORD wMinor;
	}
	--]]
	rec_func.IVER=function()
		local IVER={}
		IVER.wMajor=get_word()
		IVER.wMinor=get_word()
		return IVER
	end

	--[[
	struct sfPresetHeader
	{
		CHAR achPresetName[20];
		WORD wPreset;
		WORD wBank;
		WORD wPresetBagNdx;
		DWORD dwLibrary;
		DWORD dwGenre;
		DWORD dwMorphology;
	};
	--]]
	rec_func.phdr=function()
		local phdr={}
		phdr.achPresetName=get_name(20)
		phdr.wPreset=get_word()
		phdr.wBank=get_word()
		phdr.wPresetBagNdx=get_word()
		phdr.dwLibrary=get_long()
		phdr.dwGenre=get_long()
		phdr.dwMorphology=get_long()
		return phdr
	end

	--[[
	struct sfPresetBag
	{
		WORD wGenNdx;
		WORD wModNdx;
	};
	--]]
	rec_func.pbag=function()
		local pbag={}
		pbag.wGenNdx=get_word()
		pbag.wModNdx=get_word()
		return pbag
	end

	rec_func.ibag=function()
		local ibag={}
		ibag.wGenNdx=get_word()
		ibag.wModNdx=get_word()
		return ibag
	end


	--[[
	struct sfModList
	{
		SFModulator sfModSrcOper;
		SFGenerator sfModDestOper;
		SHORT modAmount;
		SFModulator sfModAmtSrcOper;
		SFTransform sfModTransOper;
	};
	--]]
	rec_func.pmod=function()
		local pmod={}
		pmod.sfModSrcOper=sfModulator()
		pmod.sfModDestOper=SFGenerator()
		pmod.modAmount=get_word()
		pmod.sfModAmtSrcOper=sfModulator()
		pmod.sfModTransOper=SFTransform()
		return pmod
	end


	--[[
	struct sfInstModList
	{
		SFModulator sfModSrcOper;
		SFGenerator sfModDestOper;
		SHORT modAmount;
		SFModulator sfModAmtSrcOper;
		SFTransform sfModTransOper;
	};
	--]]
	rec_func.imod=function()
		local imod={}
		imod.sfModSrcOper=sfModulator()
		imod.sfModDestOper=SFGenerator()
		imod.modAmount=get_word()
		imod.sfModAmtSrcOper=sfModulator()
		imod.sfModTransOper=SFTransform()
		return imod
	end

	--[[
	struct sfGenList
	{
		SFGenerator sfGenOper;
		genAmountType genAmount;
	};
	--]]
	rec_func.pgen=function()
		local pgen={}
		pgen.sfGenOper=SFGenerator()
		pgen.genAmount=genAmountType()
		return pgen
	end

	rec_func.igen=function()
		local igen={}
		igen.sfGenOper=SFGenerator()
		igen.genAmount=genAmountType()
		return igen
	end

	--[[
	struct sfSample
	{
		CHAR achSampleName[20];
		DWORD dwStart;
		DWORD dwEnd;
		DWORD dwStartloop;
		DWORD dwEndloop;
		DWORD dwSampleRate;
		BYTE byOriginalKey;
		CHAR chCorrection;
		WORD wSampleLink;
		SFSampleLink sfSampleType;
	};
	--]]
	rec_func.shdr=function()
		local shdr={}
		shdr.Depth=16 -- WHERE FROM ???
		shdr.achSampleName=get_name(20) -- achSampleName
		shdr.dwStart=get_long()
		shdr.dwEnd=get_long()
		shdr.dwStartloop=get_long()
		shdr.dwEndloop=get_long()
		shdr.dwSampleRate=get_long()
		shdr.byOriginalKey=get_byte() --byOriginalKey
		shdr.chCorrection=get_byte()  --get_char()
		shdr.wSampleLink=get_word()
		shdr.sfSampleType=SFSampleLink()
		return shdr
	end

	--[[
	struct sfInst
	{
		CHAR achInstName[20];
		WORD wInstBagNdx;
	};
	--]]
	rec_func.inst=function()
		local inst={}
		inst.InstrumentName=get_name(20)
		inst.wInstBagNdx=get_word()
		return inst
	end

	--[[

	<INFO-list> -> LIST (‘INFO’ {
			<ifil-ck> ; Refers to the version of the Sound Font RIFF file
			<isng-ck> ; Refers to the target Sound Engine
			<INAM-ck> ; Refers to the Sound Font Bank Name
			[<irom-ck>] ; Refers to the Sound ROM Name
			[<iver-ck>] ; Refers to the Sound ROM Version
			[<ICRD-ck>] ; Refers to the Date of Creation of the Bank
			[<IENG-ck>] ; Sound Designers and Engineers for the Bank
			[<IPRD-ck>] ; Product for which the Bank was intended
			[<ICOP-ck>] ; Contains any Copyright message
		[<ICMT-ck>] ; Contains any Comments on the Bank
		[<ISFT-ck>] ; The SoundFont tools used to create and alter the bank } )
	--]]

	local SF={}

	local function DoList(need_id)
		local list={}
		local list_id=get_id() 		Expect(list_id,"LIST")
		local list_size=get_long() 	--printf("%q %d bytes\n",list_id,list_size)
		list.size=list_size
		local info_id=get_id() 		--printf("< %s >\n",info_id) Expect(info_id,need_id)
		local have=4
		while have<list_size do
			local id=get_id()
			local sz=get_long() 	--printf("%4d:%4d:%q %5d bytes:",have,list_size,id,sz)
			if id=="smpl" then
				list[id]=fd:read(sz)
			else
				local func=rec_func[id]
				if func then
					local pose=pos()+sz
					local recs={}
					local idx=0
					while pos()<pose do
						local rec=func()
						recs[idx]=rec
						idx=idx+1
					end
					list[id]=recs
					--printf("\n")
				elseif sz>100 then
					local d=fd:read(32)
					list[id]=hex(d)
					--printf("%s...\n",hex(d))
					fd:seek("cur",sz-32)
				else
					local d=fd:read(sz)
					if d:match("^[\032-\126\r\n]+%z.*$") then
						--printf("%s\n",d:gsub("%z.*$",""))

						list[id]=d:gsub("%z.*$","")
					else
						--printf("%s\n",hex(d:sub(1,32)))
						list[id]=hex(d:sub(1,32))
					end
				end
			end
			have=have+4+4+sz
		end
		SF[info_id]=list
	end

	local function keyRange(region,pgen)
		local hilo=pgen.genAmount
		local lo=hilo%256
		local hi=(hilo-lo)/256
		region.key_hi=hi
		region.key_lo=lo
	end

	local sf_generators=
	{
		[0]="startAddrsOffset",
		"endAddrsOffset",
		"startloopAddrsOffset",
		"endloopAddrsOffset",
		"startAddrsCoarseOffset",
		"modLfoToPitch",
		"vibLfoToPitch",
		"modEnvToPitch",
		"initialFilterFc",
		"initialFilterQ",
		"modLfoToFilterFc", -- 10
		"modEnvToFilterFc",
		"endAddrsCoarseOffset",
		"modLfoToVolume",
		"unused1",
		"chorusEffectsSend",
		"reverbEffectsSend",
		"pan",
		"unused2",
		"unused3",
		"unused4", --20
		"delayModLFO",
		"freqModLFO",
		"delayVibLFO",
		"freqVibLFO",
		"delayModEnv",
		"attackModEnv",
		"holdModEnv",
		"decayModEnv",
		"sustainModEnv",
		"releaseModEnv", -- 30
		"keynumToModEnvHold",
		"keynumToModEnvDecay",
		"delayVolEnv",
		"attackVolEnv",
		"holdVolEnv",
		"decayVolEnv",
		"sustainVolEnv",
		"releaseVolEnv",
		"keynumToVolEnvHold",
		"keynumToVolEnvDecay", --40
		"instrument",
		"reserved1",
		keyRange,
		"velRange",
		"startloopAddrsCoarseOffset",
		"keynum",
		"velocity",
		"initialAttenuation",
		"reserved2",
		"endloopAddrsCoarseOffset", -- 50
		"coarseTune",
		"fineTune",
		"sampleID",
		"sampleModes",
		"reserved3",
		"scaleTuning",
		"exclusiveClass",
		"overridingRootKey",
		"unused5",
		"endOper"
	}

	local function sf_generate(reg,pgen)
		local GenOper=sf_generators[pgen.sfGenOper]
		if type(GenOper)=="function" then
			return GenOper(reg,pgen)
		end
		reg[GenOper]=pgen.genAmount
	end

	local riff_id=get_id() 		Expect(riff_id,"RIFF")
	local riff_size=get_long() --	printf("%q %d bytes\n",riff_id,riff_size)
	local sfbk_id=get_id() 		Expect(sfbk_id,"sfbk")
	-- version
	DoList('INFO')
	-- sample data
	DoList('sdta')
	-- rest
	DoList('pdta')

	local data=fd:read(30)
	if data then
		printf("data=%s\n",hex(data))
	end
	fd:close()



	local pdta=SF.pdta or error("no SF.pdta")
	--
	-- process instruments
	--
	do
		local pdta_ibag=pdta.ibag or error("no pdta.ibad") pdta.ibag=nil
		local pdta_imod=pdta.imod or error("no pdta.imod") pdta.imod=nil
		local pdta_igen=pdta.igen or error("no pdta.igen") pdta.igen=nil
		local pdta_inst=pdta.inst or error("no pdta.inst")

		local function InstrumentLoadRegions(ndx1,ndx2)
			local regions={}
			local ridx=0
			assert(ndx1)
			assert(ndx2)
			for i=ndx1,ndx2-1 do
				local gidx1=assert(pdta_ibag[i+0]).wGenNdx
				local gidx2=assert(pdta_ibag[i+1]).wGenNdx
				local midx1=assert(pdta_ibag[i+0]).wModNdx
				local midx2=assert(pdta_ibag[i+1]).wModNdx
				--printf("i=%d gidx1=%s gidx2=%s\n",i,vis(gidx1),vis(gidx2))
				--printf("i=%d midx1=%s midx2=%s\n",i,vis(midx1),vis(midx2))
				local reg={}
				for j=gidx1,gidx2-1 do
					sf_generate(reg,pdta_igen[j])
				end
				for j=midx1,midx2-1 do
					reg.modulators=reg.modulators or {}
					push(reg.modulators,pdta_imod[j])
				end
				if i==ndx1 and ndx2-ndx1>1 then
					regions.global=reg
				else
					regions[ridx]=reg
					ridx=ridx+1
				end
			end
			return regions
		end

		for i=0,#pdta_inst-1 do
			local ndx1=assert(pdta_inst[i+0]).wInstBagNdx
			local ndx2=assert(pdta_inst[i+1]).wInstBagNdx
			--printf("i=%d ndx1=%s ndx2=%s\n",i,vis(ndx1),vis(ndx2))
			pdta_inst[i].regions=InstrumentLoadRegions(ndx1,ndx2)
		end
	end

	--
	-- process presets
	--
	do

		local pdta_pbag=pdta.pbag or error("no pdta.pbad") pdta.pbag=nil
		local pdta_pmod=pdta.pmod or error("no pdta.pmod") pdta.pmod=nil
		local pdta_pgen=pdta.pgen or error("no pdta.pgen") pdta.pgen=nil
		local pdta_phdr=pdta.phdr or error("no pdta.phdr")

		local function PresetLoadRegions(ndx1,ndx2)
			local regions={}
			local ridx=0
			assert(ndx1)
			assert(ndx2)
			for i=ndx1,ndx2-1 do
				local gidx1=assert(pdta_pbag[i+0]).wGenNdx
				local gidx2=assert(pdta_pbag[i+1]).wGenNdx
				local midx1=assert(pdta_pbag[i+0]).wModNdx
				local midx2=assert(pdta_pbag[i+1]).wModNdx
				--printf("i=%d gidx1=%s gidx2=%s\n",i,vis(gidx1),vis(gidx2))
				--printf("i=%d midx1=%s midx2=%s\n",i,vis(midx1),vis(midx2))
				local reg={}
				for j=gidx1,gidx2-1 do
					sf_generate(reg,pdta_pgen[j])
				end
				for j=midx1,midx2-1 do
					reg.modulators=reg.modulators or {}
					push(reg.modulators,pdta_pmod[j])
				end
				if i==ndx1 and ndx2-ndx1>1 then
					regions.global=reg
				else
					regions[ridx]=reg
					ridx=ridx+1
				end
			end
			return regions
		end
		for i=0,#pdta_phdr-1 do
			local ndx1=assert(pdta_phdr[i+0]).wPresetBagNdx
			local ndx2=assert(pdta_phdr[i+1]).wPresetBagNdx
			--printf("i=%d ndx1=%s ndx2=%s\n",i,vis(ndx1),vis(ndx2))
			pdta_phdr[i].regions=PresetLoadRegions(ndx1,ndx2)
		end
	end

	return SF
end



local function save_sample(path,sdta_smpl,sample)

	-- data conversion helpers
	local function uint16(val)
		local a=val%256 val=(val-a)/256
		local b=val%256
		return schar(a,b)
	end

	local function uint32(val)
		local a=val%256 val=(val-a)/256
		local b=val%256 val=(val-b)/256
		local c=val%256 val=(val-c)/256
		local d=val%256 --val=(val-d)/256
		return schar(a,b,c,d)
	end

	local Start=sample.dwStart
	local End=sample.dwEnd
	local data=sdta_smpl:sub(Start*2+1,End*2)

	local fmt=join
	{
		'fmt ',
		uint32(16),	-- block size
		uint16(1),	-- format PCM
		uint16(1),	-- number channels
		uint32(sample.dwSampleRate),
		uint32(sample.dwSampleRate*2),	--  Number of bytes to read per second (Frequency * BytePerBloc).
		uint16(1*16/8),	--Number of bytes per block (NbrChannels * BitsPerSample / 8).
		uint16(16), 	--number of bits per sample
	}

	local RIFF=join
	{
		'RIFF',
		uint32(4+4+4+#fmt+4+#data-8),
		'WAVE',
		fmt,
		'data',
		uint32(#data),
		data
	}
	save_file(path,RIFF)
end

--
-- trivial data to xml
--
local function data2xml(data)
	local function d2x(dat,ind)
		if dat==nil then return "" end
		assert(type(dat)=="table")
		local tag=dat[1]
		if #dat==1 then
			return sprintf("%s<%s/>",ind,tag)
		end
		if #dat==2 and type(dat[2])~="table" then
			return sprintf("%s<%s>%s</%s>",ind,tag,tostring(dat[2]),tag)
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


local function save_drumkit(SF,drumkit_dir)
	local drumkit_name=drumkit_dir:gsub(".*/",""):gsub("drumkit%-","")

	local instrumentList={"instrumentList"}

	local sdta=SF.sdta or error("no SF.sdta")
	local sdta_smpl=sdta.smpl or error("no sdta.smpl")

	local pdta=SF.pdta or error("no SF.pdta")
	local pdta_inst=pdta.inst or error("no pdta.inst")
	local pdta_shdr=pdta.shdr or error("no pdta.shdr")

	local function is_percussion(inst)
		local regions=inst.regions
		for r=0,#regions do
			local region=regions[r]
			if not (region.key_lo and region.key_hi and region.key_lo==region.key_hi) then
				return false
			end
		end
		return true
	end

	local function find_instrument(name)
		for i=0,#pdta_inst-1 do
			local inst=pdta_inst[i]
--~ 			if is_percussion(inst) then
--~ 				printf("PERC???[%d] %q\n",#inst.regions,inst.InstrumentName)
--~ 			end
			if inst.InstrumentName==name then
				return inst
			end
		end
		return nil,"no instrument "..name
	end
	local instrument_standard=find_instrument("Standard") or find_instrument("Standard0")
	if not instrument_standard then return end

	local did_save={}
--local samples={}
	local regions=instrument_standard.regions or error("no instrument_standard.regions")
	instrument_standard.regions=nil
	--printf("instrument_standard=%s\n",vist(instrument_standard))
	for r=0,#regions do
		local region=regions[r]
		--printf("r=%s region=%s\n",r,vist(region))
		if region.sampleID and region.key_lo and region.key_hi and region.key_lo==region.key_hi then
			local sample=pdta_shdr[region.sampleID]
			--printf("s=%s sample=%s\n",region.sampleID,vist(sample))
			local dst_filename=sprintf("%s.wav",sample.achSampleName)
			if not did_save[dst_filename] then
				save_sample(drumkit_dir.."/"..dst_filename,sdta_smpl,sample)
				did_save[dst_filename]=true
			end
			local layer=
			{"layer",
				{"filename",dst_filename},
				{"startframe",0},
				{"loopframe",sample.dwStartloop-sample.dwStart},
				{"endframe",sample.dwEnd-sample.dwStart},
				{"loops",region.sampleModes},
				-- both bad
				--{"pitch",sample.byOriginalKey},
				--{"pitch",region.key_lo},
			}

			--local release=region.releaseVolEnv
			--local Attack=region.attackVolEnv

			local instrumentComponent={"instrumentComponent",layer}
			local instrument=
			{"instrument",
				{"id",r+1},
				{"name",sprintf("%s (%d)",sample.achSampleName,region.key_lo)},
				{"midiOutNote",region.key_lo},
				{"pitchOffset",region.key_lo-(region.overridingRootKey or sample.byOriginalKey)},
				--{"pitchOffset",region.key_lo-(region.overridingRootKey or 60)},
				--{"pitchOffset",60-(region.overridingRootKey or 60)},
				{"Attack",0},
				{"Decay",0},
				{"Sustain",1},
				{"Release",1000},
				--{"Decay",Decay},
				--{"Hold",Hold},
				--{"Release",Release},
				--{"Sustain",Sustain},
				instrumentComponent
			}
			table.insert(instrumentList,instrument)

		end
	end
	local INFO=SF.INFO or error("no SF.INFO")
	--
	--SF.INFO={ICMT="960920 ver. 1.00.16",
	-- ICOP="Copyright 1996 Roland Corporation U.S.",--
	-- IENG="Roland Corporation",INAM="gm.sf2",
	-- ISFT="dls_cnv v0.27y",ifil="02000100",size=160}

	local drumkit_info=
	{"drumkit_info",
		{"name",drumkit_name},
		{"info",sprintf("Created from %s",INFO.INAM)},
		{"license",INFO.ICMT},
		instrumentList}
	--save_data("drumkit.data",drumkit_info)
	printf("save_file(%q)\n",drumkit_dir.."/drumkit.xml")
	save_file(drumkit_dir.."/drumkit.xml",data2xml(drumkit_info))
	--os.exit()
end

local function sound_font_to_drumkit(sf2_path)
	local name=sf2_path:gsub(".*/",""):gsub("%.%w+$","")
	local SF=read_soundfont(sf2_path)
	local sdta=SF.sdta SF.sdta=nil -- dont dump

	local HOME=os.getenv("HOME") or error("no env HOME")
	local DRUMKIT_DIR=HOME.."/.hydrogen/data/drumkits/"..name
	lfs.mkdir(DRUMKIT_DIR)
	for entry in lfs.dir(DRUMKIT_DIR) do
		if entry~="." and entry~=".." then
			os.remove(DRUMKIT_DIR.."/"..entry)
		end
	end
	SF.sdta=sdta
	save_drumkit(SF,DRUMKIT_DIR)

end

sound_font_to_drumkit("/usr/share/sounds/sf2/windows7-gm.sf2")
sound_font_to_drumkit("/usr/share/sounds/sf2/sf_GMbank.sf2")
sound_font_to_drumkit("/usr/share/sounds/sf2/TimGM6mb.sf2")
--sound_font_to_drumkit("/usr/share/sounds/sf2/FluidR3_GS.sf2")
--sound_font_to_drumkit("/usr/share/sounds/sf2/FluidR3_GM.sf2")
