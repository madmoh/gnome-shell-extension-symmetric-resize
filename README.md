# Symmetric Resize

[demo.webm](https://github.com/user-attachments/assets/9ff2b165-e9f7-4657-8f22-83886c01054b)

Resize GNOME windows from the center or with a fixed aspect ratio while a modifier key is held.

## About

Symmetric Resize changes how a mouse resize behaves while a modifier key is held. It works from any window edge or corner:

| Key | Behavior |
| --- | --- |
| Ctrl | The window resizes around its center. Opposite edges move by the same amount. |
| Shift | The window keeps its aspect ratio. A corner follows the axis dragged further. An edge scales the other axis around its center. |
| Ctrl+Shift | Both of the above. |

The keys can be pressed or released during a resize. Without them, GNOME resizes windows as usual. Each behavior can be assigned to Shift, Ctrl, Alt, Super or Disabled in the extension preferences.

When a mouse resize starts, the extension records the window frame and pointer position. While a modifier key is held, it takes the pointer motion events of the resize and sets the window size and position from those starting values with `move_resize_frame`. Other motion events go to GNOME Shell unchanged. The extension does no work outside a mouse resize.

GNOME Shell uses Shift during a resize to snap window edges to screen and window edges. This snapping does not apply while the aspect ratio key is held. Assign the aspect ratio to another key to keep it.

## Install from packaged releases

Download `symmetric-resize@madmoh.github.io.shell-extension.zip` from the [releases page](https://github.com/madmoh/gnome-shell-extension-symmetric-resize/releases). Then install it:

```sh
gnome-extensions install --force symmetric-resize@madmoh.github.io.shell-extension.zip
```

Sign out and sign in. Then enable the extension:

```sh
gnome-extensions enable symmetric-resize@madmoh.github.io
```

## Install from source

```sh
git clone https://github.com/madmoh/gnome-shell-extension-symmetric-resize.git
cd gnome-shell-extension-symmetric-resize
make install
```

Sign out and sign in. Then enable the extension:

```sh
gnome-extensions enable symmetric-resize@madmoh.github.io
```

## Testing

Check the sources with Node.js and create the package:

```sh
make lint
make pack
```

Run the end-to-end test on a machine with GNOME Shell 50. The test starts a separate headless GNOME Shell with temporary settings. It does not change the running session. Choose the machine explicitly:

```sh
make e2e TARGET=local
make e2e TARGET=user@host
```
