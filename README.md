# pipesplit

Split application audio into independent headphone and stream channels on Linux. Built for streamers who want per-app volume control in OBS without touching a patch bay.

![audio-controll](/home/nero/Documents/Coding/pipesplit/audio-controll.png)

**pipesplit** creates virtual PipeWire sinks, automatically routes applications to them, and lets you toggle between output devices with a keybind.

## TODO

```
[] Add simple config file for Output Devices
[] Cycle through devices instead of toggle
```



```
                    ┌─────────────┐
 Spotify ──────┬───▶│  hp-music   │──▶ Headphones
               │    └─────────────┘
               └───▶│ stream-music│──▶ OBS (independent fader)
                    └─────────────┘

                    ┌─────────────┐
 Game ─────────┬───▶│  hp-games   │──▶ Headphones
               │    └─────────────┘
               └───▶│ stream-games│──▶ OBS (independent fader)
                    └─────────────┘
```

## Features

- **Auto-routing** — a background daemon watches for apps and splits their audio to both sinks automatically
- **Per-app config** — simple text file maps app names to sink pairs
- **Output toggle** — switch between headphone devices with one command or keybind
- **Survives reboots** — virtual sinks are created by PipeWire config, not scripts
- **No GUI needed** — works headless, but plays nice with qpwgraph for visual debugging

## Requirements

- PipeWire with WirePlumber
- `pw-link` and `pw-cli` (included with PipeWire)
- `notify-send` (optional, for desktop notifications)

## Install

```bash
git clone https://github.com/pymmog/pipesplit.git
cd pipesplit
chmod +x install.sh
./install.sh
```

Then:

```bash
systemctl --user restart pipewire         # create virtual sinks
systemctl --user enable --now pipesplit    # start auto-router on login
pipesplit connect                          # link headphone sinks to output device
```

## Quick start

### 1. Configure your apps

Edit `~/.config/pipesplit/routes.conf`:

```conf
spotify         = hp-music, stream-music
.exe            = hp-games, stream-games
```

The left side is a substring match against PipeWire node names. Find running app names with:

```bash
pw-link -ol | grep -oP '^[^:]+' | sort -u
```

### 2. Configure your output devices

Edit the `DEVICES` array in `~/.local/bin/pipesplit` if your devices differ from the defaults (Sound Blaster X4 and Elgato Wave XLR).

### 3. Set app outputs

In your system sound settings, set each application's output to:

- Games → **Headphones-Games**
- Music → **Headphones-Music**

PipeWire remembers per-app assignments. You only do this once.

### 4. Set up OBS

Add **Audio Input Capture (PipeWire)** sources in OBS:

- **Stream-Games** for game audio
- **Stream-Music** for music

Each gets an independent volume fader in OBS's mixer.

## Usage

```bash
pipesplit                   # connect to last-used output device
pipesplit toggle            # switch between output devices
pipesplit soundblaster      # force Sound Blaster X4
pipesplit elgato            # force Elgato Wave XLR
pipesplit status            # show sinks, router state, and links
pipesplit stop              # stop the auto-router
```

### Hyprland keybind

```
bind = SUPER, F8, exec, ~/.local/bin/pipesplit toggle
```

## Adding sinks

Add a new sink pair to `sinks.conf` and restart PipeWire:

```conf
# In ~/.config/pipewire/pipewire.conf.d/pipesplit.conf
{
    factory = adapter
    args = {
        factory.name   = support.null-audio-sink
        node.name       = hp-voice
        node.description = "Headphones-voice"
        media.class     = Audio/Sink
        audio.position  = [ FL FR ]
        monitor.channel-volumes = true
        monitor.passthrough = true
    }
}
```

Then add the route and update the `HP_SINKS` array in the main script:

```conf
# ~/.config/pipesplit/routes.conf
discord = hp-voice, stream-voice
```

```bash
# In ~/.local/bin/pipesplit
HP_SINKS=("hp-games" "hp-music" "hp-voice")
```

## How it works

**Virtual sinks** are defined in a PipeWire config drop-in (`pipesplit.conf`). PipeWire creates them automatically on startup — no scripts, no race conditions.

**The auto-router** (`pipesplit-router`) is a lightweight bash daemon that polls PipeWire every 2 seconds. When it sees an app matching a pattern in `routes.conf`, it connects the app to both its headphone and stream sink, and disconnects it from any hardware output that WirePlumber may have assigned.

**Output switching** disconnects all headphone sinks from all output devices, then reconnects them to the target device only.

## Troubleshooting

**Sinks don't appear** — check config location and restart PipeWire:

```bash
ls ~/.config/pipewire/pipewire.conf.d/pipesplit.conf
systemctl --user restart pipewire
```

**App not being routed** — check the router is running and the app name matches:

```bash
pipesplit status
pw-link -ol | grep -oP '^[^:]+' | sort -u
journalctl --user -u pipesplit -f
```

**Audio on wrong device after toggle** — run `pipesplit status` and check for stray links.

**Double audio / echo** — some apps reconnect to hardware on their own. The router removes these stray links every 2 seconds, but there may be brief moments of overlap.

## Files

```
pipesplit.conf           PipeWire config — creates virtual sinks on boot
routes.conf              App-to-sink mapping
pipesplit                Main script — output switching and management
pipesplit-router         Auto-routing daemon
pipesplit.service        Systemd user unit for the router
pipesplit.desktop        Desktop launcher
install.sh               Installer
```
