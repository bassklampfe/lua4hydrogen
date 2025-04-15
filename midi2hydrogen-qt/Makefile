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

# Generate object files, rule to change postfix
%.o: %.cpp Makefile
	$(CXX) $(CFLAGS) $(INCDIRS) -c $< -o $@


$(EXECUTABLE): $(OBJECTS)
	$(CXX) $^ $(LIBS) -o $@
