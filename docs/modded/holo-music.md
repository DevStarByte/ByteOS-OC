# Holograms and music

Two packages for show: `holo` draws text and shapes on OpenComputers' **hologram
projector**, and `play` plays tunes on the computer's speaker or on **note blocks**.

## Holograms

Place a hologram projector, connect it to the computer by cable, and install `holo`:

```sh
root@byteos ~# pacman -S holo
alice@byteos ~> holo demo          # a little show
```

The projector has 48 × 32 × 48 *voxels* (3D pixels). A **tier 1** projector shows one
colour, a **tier 2** projector three, and only tier 2 can rotate the hologram.

| Command | What it does |
|---|---|
| `holo clear` | switch every voxel off |
| `holo text "HI" [COLOR]` | letters, centred and as big as fit |
| `holo shape cube/sphere/pyramid [SIZE] [COLOR]` | a solid shape in the middle; SIZE in voxels (default 16, at most 32) |
| `holo color N 0xRRGGBB` | what colour N looks like |
| `holo scale S` | the hologram's size, from 0.33 to 3 |
| `holo spin [SPEED]` | turn it, degrees per second (default 30, `0` stops; tier 2) |
| `holo demo` | a little show |

For `shape`, give one of the words: `holo shape sphere`. `COLOR` is 1, 2 or 3 on a
tier 2 projector; on tier 1 every colour is 1.

```sh
alice@byteos ~> holo clear
alice@byteos ~> holo text "BASE" 2
alice@byteos ~> holo color 2 0xFF8800      # colour 2 becomes orange
alice@byteos ~> holo shape sphere 24 3
alice@byteos ~> holo scale 2
alice@byteos ~> holo spin 20
```

Text knows the letters A-Z, the digits 0-9 and `! ? . - :`; lower case is drawn as upper
case. Up to 8 characters fit. A shape's middle lies between two voxels, so an odd SIZE is
drawn one smaller.

Drawing takes many calls to the projector, so big pictures take a moment; `holo` pauses
now and then so that the computer is not stopped for running too long.

!!! note "Tested against simulated hardware"
    `holo` is tested against a simulated projector with OpenComputers' hologram API. If
    your version behaves differently (older versions have a shorter `fill`), tell us on
    [GitHub](https://github.com/DevStarByte/ByteOS-OC/issues).

## Music

```sh
root@byteos ~# pacman -S play
alice@byteos ~> play -l               # the songs that come with it
fur-elise       Für Elise, the opening (Beethoven)
korobeiniki     Korobeiniki (Russian folk song, the Tetris theme)
ode-to-joy      Ode to Joy (Beethoven, Symphony No. 9)
twinkle         Twinkle, Twinkle, Little Star (traditional)
alice@byteos ~> play ode-to-joy
alice@byteos ~> play -t 160 korobeiniki      # faster
alice@byteos ~> play -n "C4 E4 G4 C5*2"      # notes right on the command line
```

++ctrl+c++ stops a song.

### Where the sound comes from

- With **note blocks** connected, `play` uses them: Computronics **iron note blocks**
  (connected by cable), or vanilla **note blocks** next to an OpenComputers **Adapter**.
  All of them play together. Note blocks cover two octaves (F#3 to F#5); notes outside
  are moved by whole octaves into that range.
- Without note blocks, the computer's own **speaker** beeps. It covers 20 to 2000 Hz;
  notes outside that are skipped with a warning.
- `-s` uses the speaker even when there are note blocks.

### Writing songs

A song is a text file of notes, read left to right:

```text
# Ode to Joy
tempo 120
E4 E4 F4 G4 | G4 F4 E4 D4 | C4 C4 D4 E4 | E4. D4/2 D4*2
```

| Write | Means |
|---|---|
| `C4`, `F#4`, `Bb3` | a note: a letter A-G, `#` (sharp) or `b` (flat), and an octave 0-8. `A4` is 440 Hz, `C4` is middle C. |
| `C4*2` | twice as long (a note lasts one beat by default) |
| `C4/2` | half as long |
| `C4.` | half as long again (one and a half beats) |
| `R`, `R/2` | a rest |
| <code>&#124;</code> | ignored: use it as a bar line |
| `tempo 120` | beats per minute (default 120; `-t` overrides it) |
| `# ...` | a comment (a `#` at the start of a word) |

Save the file anywhere and play it by its path (`play ~/songs/mine.txt`). Files in
`/usr/share/play/` (as root) can be played by name and show up in `play -l`; the first
line's comment is the title it shows.

If a note is wrong, `play` names the file, the line and the word:

```text
play: mine.txt, line 4: not a note: X9
```
