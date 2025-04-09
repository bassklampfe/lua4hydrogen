# lua4hydrogen
Lua scripts to create hydrogen drumkits from soundfonts and hydrogen songs from midi

# WHAT IS THIS ??

Two lua scripts

- **midi_to_hydrogen** : convert a midi file into a hydrogen song
- **sf2_to_drumkit** : convert a sound font into a hydrogen drumkit

## How to install

I known, only a few people use lua, so here are the steps required for a standard ubuntu to install everything needed to run the scripts:

    sudo apt install lua5.1 luajit lua-file-system lua5.1-doc lua-socket lua-sec
    sudo mkdir -p /usr/local/share/lua/5.1
    sudo cp /usr/share/doc/lua5.1-doc/etc/strict.lua /usr/local/share/lua/5.1/

NOTE: not all of these packages are required for these particular scripts, but this is my standard setup, which works almost everywhere.

As IDE I prefer [Zerobrane-Studio](https://studio.zerobrane.com/) (an IDE written completely in lua itself).
You can download and install manually or use the following commands:

    wget https://download.zerobrane.com/ZeroBraneStudioEduPack-2.01-linux.sh
    bash ZeroBraneStudioEduPack-2.01-linux.sh


## Get soundfonts and convert do hydrogen drumkits  

Soundfonts I prefer:

- **TimGM6mb.sf2** : Soundfont from MuseScore 1.3. Can be installed with  
  `sudo apt install timgm6mb-soundfont`
- **gm.sf2** : (I renamed it to **windows7-gm.sf2**)   
  not pretty but very clear in its sounds. Found e.g. here [Default Windows MIDI Soundfont](https://musical-artifacts.com/artifacts/713)  
   Copy to `/usr/share/sounds/sf2/` so it can be used by all software in your system.  
- **sf_GMbank.sf2** : Soundfont from csound. Can be installed with  
  `sudo apt install csound-soundfont`


  
Then run   
  
`luajit sf2_to_drumkit.lua`   
  
and you will find 3 new drumkits in `~/.hydrogen/data/drumkits/`  
  
If you want to try other soundfonts, just edit the last lines in `sf2_to_drumkit.lua`. But be aware of not all soundfonts have clearly identifyable drumkits, so the script may fail.
  
## Convert midi file to hydrogen song

Just run

`luajit midi_to_hydrogen.lua` *midifile*

and you will find a h2song aside from the midi files (+ some additional debug files)  
Preselected drumkit is TimGM6mb, you can override this by  passing an environment variable:  

`DRUMKIT="windows7-gm" luajit midi_to_hydrogen.lua` *midifile*

# History
  
## hydrogen  

It all began, as I became aware of hydrogren. "WOW what a tool", now I have a drummer in my computer. :-) 

The disillusionment began when I wanted to import a midi-file. (As a hunter and collector I have about 356000 (!) midi files in my collection)
  
I had to learn hydrogen cant do that. So I searched the internet and became aware of **[midi2hydrogen](https://github.com/RushOnline/midi2hydrogen)**.   
  
Next disillusionment: Almost every expectation was *not* fulfilled. No tempo, no signature, no pattern recognition.

## midi_to_hydrogen

That's when I began on `midi_to_hydrogen` . It does everything in the right way.
  
- midi file is parsed and drum tracks are extracted.
- repeated patterns are detected and merged into one pattern, which is then reused.
- tempo and signature changes are recognized.
- a hydrogen drumkit is loaded and matching instruments are associated to midi pitches.
- finally a hydrogen song (.h2song) is written with the result.

But OH, this did not nearly sound like the original midi file. Why? Because not all midi pitches could be successfully assigned to a matching hydrogen instrument.

So I started phase 2

## sf2_to_drumkit

I had some soundfonts which I really like in Midi playback and so I wrote another script to extract the samples from a soundfont and create a drumkit which then can be used by hydrogen.

## Finally
  
And, YES, now it works like a charm. There will still be issues and improvements, but the basic fundament is done.
  
## Last question: Why Lua ?!?  
  
Well, Lua is the language I prefer because of its small overhead (the lua interpreter itself is about 200kb and basically depends only on libc, libm, libdl and libreadline)  
  
And Lua is fast. On my machine sf2_to_drumkit takes about 1/4 sec to convert 3 soundfiles to drumkits, midi_to_hydrogen takes typically << 1/10 sec for a midi file. Using luajit these times can even be half of the size.

It should even be possible to integrate lua engine + midi_to_hydrogen into hydrogen with a few lines of code. I will try in one of the next weeks...


