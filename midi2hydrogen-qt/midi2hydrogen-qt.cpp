#include <iostream>
#include <QString>
#include <lua.hpp>


QString MidiToHydrogen(const QString&midi_to_hydrogen_lua,const QString&midi_file)
{
	int status;
	//
	// open a lua state
	//
	lua_State *L = lua_open();
	luaL_openlibs(L);

	//
	// load the script
	//
	status=luaL_loadfile(L, midi_to_hydrogen_lua.toStdString().c_str());
	if(status!=0)
	{
		QString message=lua_tostring(L,-1);
		lua_close(L);
		throw  QString("luaL_loadfile failed:")+message;
	}

	//
	// run the script to set midi_to_hydrogen into globals
	//
	status = lua_pcall(L, 0,0,0);
	if(status!=0)
	{
		QString message=lua_tostring(L,-1);
		lua_close(L);
		throw QString("lua_pcall failed:")+message;
	}

	//
	// call lua function midi_to_hydrogen(midi_file)
	//
	lua_getglobal(L,"midi_to_hydrogen");
	lua_pushstring(L, midi_file.toStdString().c_str());
    status = lua_pcall(L, 1,1,0);
	if(status!=0)
	{
		QString message=lua_tostring(L,-1);
		lua_close(L);
		throw QString("lua_pcall failed:")+message;
	}

	QString h2song=lua_tostring(L,-1);
	lua_close(L);
	return h2song;
}

int main(int argc,const char*argv[])
{
	for(int n=1;n<argc;++n)
	{
		try
		{
			QString h2song=MidiToHydrogen("../midi_to_hydrogen.lua",argv[n]);
			std::cout<<h2song.toStdString()<<"\n";
		}
		catch(const QString msg)
		{
			std::cerr<<msg.toStdString()<<"\n";
		}
	}
}
