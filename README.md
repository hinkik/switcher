# Switcher

Lightweight macOS app launcher. A dmenu-style alternative to Spotlight that only searches applications.

## Features

- **Fast** — native Swift, no Electron, no frameworks
- **Fuzzy search** — type a few characters to find any app
- **Priority apps** — Terminal, Firefox, Word, Excel, Outlook, PowerPoint, VS Code, and Codex are boosted in results
- **Global hotkey** — Option+Space (or Cmd+Space if Spotlight's hotkey is disabled)
- **Menu bar icon** — click ⌘ to search or quit

## Build

```
swift build -c release
```

## Run

```
open Switcher.app
```

Or directly:

```
.build/release/Switcher
```

## Install

```
cp -r Switcher.app /Applications/
```

To start at login, add Switcher to **System Settings > General > Login Items**.

To use Cmd+Space, disable Spotlight's hotkey in **System Settings > Keyboard > Keyboard Shortcuts > Spotlight**.

## Usage

| Key | Action |
|-----|--------|
| Option+Space | Open/close search |
| ↑ / ↓ | Navigate results |
| Enter | Launch app |
| Escape | Close |
