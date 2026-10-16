<p align="center">
  <img src="docs/icon.png" width="128" alt="App icon: 4/4 in navy, brown and sage">
</p>

# Metronome

A free, one-screen metronome for iPhone and iPad. No ads, no accounts, no settings pages: everything you need is on the screen at once.

<p align="center">
  <img src="docs/iphone.png" height="520" alt="iPhone, portrait">
  &nbsp;
  <img src="docs/ipad.png" height="520" alt="iPad, portrait">
</p>

<p align="center">
  <img src="docs/iphone-landscape.png" width="640" alt="iPhone, landscape">
</p>

## Features

- **Sample-accurate timing.** The click is generated on the audio thread by counting samples, so it never drifts, and tempo changes apply instantly.
- **Tempo from 1 to 300 BPM**: a slider, hold-to-repeat +/− buttons, eight presets, tap tempo, or type it on a pop-up keypad.
- **Time signatures.** Any number of beats per bar, over a note value of 1, 2, 4, 8, 16, 32 or 64. With the time signature on, the first beat of each bar is accented and the click follows the note value (so 6/8 clicks eighth notes).
- **Three click sounds**: Classic, Wood and Electric, all synthesised in code.
- **Eight colour palettes**, cycled from the button in the top right. Your choice is remembered.
- **A live metronome** replaces the title while it's playing, its arm swinging in time with what you hear.
- **Keeps playing in the background** and with the screen locked; stops cleanly for phone calls.
- **Portrait and landscape**, scaled up properly on iPad.

Buttons respond the instant they're touched, with no fades, and RESET lights up only when there's something to reset.

## Running it

You'll need Xcode with the iOS 27 SDK. The app targets iOS 27.

1. Open `Metronome.xcodeproj`.
2. Pick an iPhone or iPad (a Simulator or a connected device) from the device menu.
3. Press **⌘R**.

To run on your own device, choose your Apple ID under *Signing & Capabilities*, and turn on Developer Mode on the device. There are no dependencies to install.

## Project layout

| File | What it does |
|---|---|
| `Metronome.swift` | The audio engine: sample-counted clicks, accents, bar tracking, and the beat clock the visuals follow |
| `ClickSound.swift` | Synthesises the three click sounds |
| `ContentView.swift` | The single screen and its layout for portrait, landscape and iPad |
| `Controls.swift` | Instant-response buttons, the slider, glyph-outline text, and the live metronome |
| `Keypad.swift` | The pop-up number pad and note-value picker |
| `Palette.swift` | The colour palettes |
| `Wobble.swift`, `Dancer.swift` | You'll see |

## Easter egg

<details>
<summary>Spoilers</summary>

Tap **METRONOME APP** and everything shivers. Tap faster and the shaking builds until the pieces fall off the screen, the title last of all. Clear the screen and something new lands in its place: a stick-figure dancer that dances in time with the click, changes move every bar (or when tapped), and waits about impatiently while the metronome is stopped.

Dance every move and someone else joins in. RESET puts everything back.

</details>
