CXX=g++

INCDIRS=\
	-I/usr/include/x86_64-linux-gnu/qt5 \
	-I/usr/include/x86_64-linux-gnu/qt5/QtGui \
	-I/usr/include/x86_64-linux-gnu/qt5/QtCore \
	-I/usr/include/lua5.1/

LIBS=\
	/usr/lib/x86_64-linux-gnu/libQt5Core.so.5 \
	/usr/lib/x86_64-linux-gnu/liblua5.1.so


SOURCES=midi2hydrogen-qt.cpp
EXECUTABLE=midi2hydrogen-qt

OBJECTS=$(SOURCES:.cpp=.o)


CFLAGS :=-fPIC

all: midi2hydrogen-qt
	./midi2hydrogen-qt GMDRUMS.mid


LUA_SCRIPT=../midi_to_hydrogen.lua
LUA_SCRIPT_HEADER=midi_to_hydrogen.lua-hh

$(LUA_SCRIPT_HEADER) : $(LUA_SCRIPT) Makefile
	(echo 'static const char midi_to_hydrogen_script[]=R"lua(';grep -v "^#!" $<;echo ')lua";') > $@

# Generate object files, rule to change postfix
%.o: %.cpp Makefile $(LUA_SCRIPT_HEADER)
	$(CXX) $(CFLAGS) $(INCDIRS) -c $< -o $@


$(EXECUTABLE): $(OBJECTS)
	$(CXX) $^ $(LIBS) -o $@
