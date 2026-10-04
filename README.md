# Knob

A minimal macOS menu bar app that makes your keyboard's volume knob (e.g. Keychron) work when your Mac outputs audio over **HDMI / DisplayPort** — the case where macOS greys out the volume control.

## How it works

Knob intercepts the volume keys only when the current output has no volume control of its own, and then uses one of two methods:

| Method | What it does |
|---|---|
| **Auto** (default) | Built-in speakers / headphones → macOS handles the keys as usual. HDMI → tries the monitor first, falls back to software. |
| **Monitor** | Sets the monitor's own volume via DDC/CI. Speakers connected to the monitor's AUX out usually follow it. |
| **Software** | Routes system audio through a Core Audio process tap and applies the volume before it reaches the output. No driver needed. |

- Knob turn → volume in 16 steps, hold **⌥⇧** for fine steps
- Knob press → mute
- Minimal on-screen HUD (Liquid Glass on macOS 26+), follows light/dark mode
- Menu bar slider, method picker, launch at login

## Requirements

- Apple Silicon Mac, macOS 14.2 or later
- Xcode / Swift toolchain to build

## Build

```bash
./build.sh            # builds build/Knob.app
./build.sh --install  # also copies it to /Applications
```

On first launch, allow **Accessibility** (to catch the volume keys) and **System Audio Recording** (for software mode).
The app is ad-hoc signed, so after rebuilding you need to re-allow Accessibility.

For monitor mode, enable **DDC/CI** in your monitor's on-screen menu. Some USB-C adapters don't pass DDC through.
