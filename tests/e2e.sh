#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ] || [ -z "$1" ]; then
    echo "Usage: $0 local|SSH_DESTINATION" >&2
    exit 2
fi

root=$(cd "$(dirname "$0")/.." && pwd)

if [ "$1" != local ]; then
    tar -C "$root" -c src tests/e2e.sh | ssh "$1" 'd=$(mktemp -d) && trap "rm -rf \"\$d\"" EXIT && tar -C "$d" -x && bash "$d/tests/e2e.sh" local'
    exit
fi

uuid=$(sed -n 's/.*"uuid": "\(.*\)".*/\1/p' "$root/src/metadata.json")
display=symmetric-resize-e2e-$$

if [ -z "${SYMMETRIC_RESIZE_E2E:-}" ]; then
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    extensions=$tmp/data/gnome-shell/extensions
    mkdir -p "$extensions/e2e@symmetric-resize" "$tmp/config/glib-2.0/settings"
    cp -r "$root/src" "$extensions/$uuid"
    glib-compile-schemas "$extensions/$uuid/schemas"
    printf '{"uuid": "e2e@symmetric-resize", "name": "E2E", "description": "E2E", "shell-version": ["50"]}\n' >"$extensions/e2e@symmetric-resize/metadata.json"
    printf 'export default class { enable() { global.context.unsafe_mode = true; } disable() {} }\n' >"$extensions/e2e@symmetric-resize/extension.js"
    cat >"$tmp/config/glib-2.0/settings/keyfile" <<EOF
[org/gnome/shell]
enabled-extensions=['$uuid', 'e2e@symmetric-resize']
welcome-dialog-last-shown-version='999'

[org/gnome/desktop/interface]
enable-animations=false
enable-hot-corners=false
EOF
    SYMMETRIC_RESIZE_E2E=$tmp XDG_DATA_HOME=$tmp/data XDG_CONFIG_HOME=$tmp/config GSETTINGS_BACKEND=keyfile \
        dbus-run-session -- bash "$0" local 3>&2 2>"$tmp/dbus.log"
    exit
fi

exec 2>&3 3>&-

evaluate() {
    local reply
    reply=$(gdbus call --session --dest org.gnome.Shell --object-path /org/gnome/Shell --method org.gnome.Shell.Eval "$1" 2>/dev/null) || return 1
    [[ $reply == "(true, "* ]] || return 1
    reply=${reply#"(true, '"}
    printf '%s\n' "${reply%"')"}"
}

wait_for() {
    for _ in $(seq 100); do
        [ "$(evaluate "$1" || true)" = true ] && return
        sleep 0.2
    done
    echo "Timed out waiting for: $1" >&2
    return 1
}

gnome-shell --headless --wayland --no-x11 --virtual-monitor 1920x1200 --wayland-display "$display" >"$SYMMETRIC_RESIZE_E2E/shell.log" 2>&1 &
shell=$!
trap 'kill $(jobs -p) 2>/dev/null; wait' EXIT
wait_for 'global.context.unsafe_mode'
wait_for "Main.extensionManager.lookup('$uuid')?.state === 1"
wait_for '!Main.layoutManager._startingUp && (Main.overview.hide(), !Main.overview.visible && !Main.overview.animationInProgress)'

WAYLAND_DISPLAY=$display GDK_BACKEND=wayland GTK_A11Y=none gjs -c "
imports.gi.versions.Gtk = '4.0';
const {Gtk, GLib} = imports.gi;
Gtk.init();
new Gtk.Window({title: 'Symmetric Resize E2E', default_width: 600, default_height: 400}).present();
new GLib.MainLoop(null, false).run();
" >"$SYMMETRIC_RESIZE_E2E/window.log" 2>&1 &
wait_for "global.get_window_actors().some(a => a.meta_window.title === 'Symmetric Resize E2E')"

evaluate "$(cat <<EOF
(() => {
    const {Clutter, GLib} = imports.gi;
    const seat = Clutter.get_default_backend().get_default_seat();
    const pointer = seat.create_virtual_device(Clutter.InputDeviceType.POINTER_DEVICE);
    const keyboard = seat.create_virtual_device(Clutter.InputDeviceType.KEYBOARD_DEVICE);
    const window = global.get_window_actors().map(a => a.meta_window).find(w => w.title === 'Symmetric Resize E2E');
    const settings = Main.extensionManager.lookup('$uuid').stateObj.getSettings();
    const keys = {ctrl: 0xffe3, shift: 0xffe1, alt: 0xffe9, super: 0xffeb};
    const handles = {nw: [397, 297, -1, -1], n: [700, 297, 0, -1], ne: [1003, 297, 1, -1], e: [1003, 500, 1, 0], se: [1003, 703, 1, 1], s: [700, 703, 0, 1], sw: [397, 703, -1, 1], w: [397, 500, -1, 0]};
    const now = () => GLib.get_monotonic_time();
    const sleep = ms => new Promise(resolve => GLib.timeout_add(0, ms, () => resolve()));
    const rect = () => { const r = window.get_frame_rect(); return [r.x, r.y, r.width, r.height].join(','); };
    const press = (list, state) => list.forEach(k => keyboard.notify_keyval(now(), keys[k], state));
    const grabActors = new Set();
    const grabSignal = global.display.connect('grab-op-begin', () => grabActors.add(global.stage.get_grab_actor()));
    const drag = async (handle, first, second) => {
        Main.overview.hide();
        for (let i = 0; i < 100 && rect() !== '400,300,600,400'; i++) {
            if (i % 10 === 0)
                window.move_resize_frame(false, 400, 300, 600, 400);
            await sleep(20);
        }
        await sleep(100);
        const [x, y, hx, hy] = handles[handle];
        pointer.notify_absolute_motion(now(), x, y);
        await sleep(50);
        pointer.notify_button(now(), 1, 1);
        await sleep(50);
        press(first, 1);
        for (let i = 1; i <= 20; i++) {
            if (i === 11) {
                press(first.filter(k => !second.includes(k)), 0);
                press(second.filter(k => !first.includes(k)), 1);
            }
            pointer.notify_absolute_motion(now(), x + hx * 5 * i, y + hy * 3 * i);
            await sleep(30);
        }
        await sleep(200);
        const held = rect();
        pointer.notify_button(now(), 1, 0);
        await sleep(50);
        press(second, 0);
        await sleep(300);
        return [held, rect()];
    };
    const cases = [
        ['control', 'shift', 'se', [], [], '400,300,700,460'],
        ['control', 'shift', 'se', [], ['ctrl'], '300,240,800,520'],
        ['control', 'shift', 'se', [], ['shift'], '400,300,700,467'],
        ['control', 'shift', 'se', [], ['ctrl', 'shift'], '300,234,800,533'],
        ['control', 'shift', 'e', [], [], '400,300,700,400'],
        ['control', 'shift', 'e', [], ['ctrl'], '300,300,800,400'],
        ['control', 'shift', 'e', [], ['shift'], '400,267,700,467'],
        ['control', 'shift', 'e', [], ['ctrl', 'shift'], '300,234,800,533'],
        ['control', 'shift', 'w', [], [], '300,300,700,400'],
        ['control', 'shift', 'w', [], ['ctrl'], '300,300,800,400'],
        ['control', 'shift', 'w', [], ['shift'], '300,267,700,467'],
        ['control', 'shift', 'w', [], ['ctrl', 'shift'], '300,234,800,533'],
        ['control', 'shift', 'n', [], [], '400,240,600,460'],
        ['control', 'shift', 'n', [], ['ctrl'], '400,240,600,520'],
        ['control', 'shift', 'n', [], ['shift'], '355,240,690,460'],
        ['control', 'shift', 'n', [], ['ctrl', 'shift'], '310,240,780,520'],
        ['control', 'shift', 's', [], [], '400,300,600,460'],
        ['control', 'shift', 's', [], ['ctrl'], '400,240,600,520'],
        ['control', 'shift', 's', [], ['shift'], '355,300,690,460'],
        ['control', 'shift', 's', [], ['ctrl', 'shift'], '310,240,780,520'],
        ['control', 'shift', 'nw', [], [], '300,240,700,460'],
        ['control', 'shift', 'nw', [], ['ctrl'], '300,240,800,520'],
        ['control', 'shift', 'nw', [], ['shift'], '300,233,700,467'],
        ['control', 'shift', 'nw', [], ['ctrl', 'shift'], '300,234,800,533'],
        ['control', 'shift', 'ne', [], [], '400,240,700,460'],
        ['control', 'shift', 'ne', [], ['ctrl'], '300,240,800,520'],
        ['control', 'shift', 'ne', [], ['shift'], '400,233,700,467'],
        ['control', 'shift', 'ne', [], ['ctrl', 'shift'], '300,234,800,533'],
        ['control', 'shift', 'sw', [], [], '300,300,700,460'],
        ['control', 'shift', 'sw', [], ['ctrl'], '300,240,800,520'],
        ['control', 'shift', 'sw', [], ['shift'], '300,300,700,467'],
        ['control', 'shift', 'sw', [], ['ctrl', 'shift'], '300,234,800,533'],
        ['control', 'shift', 'se', ['ctrl'], ['ctrl'], '300,240,800,520'],
        ['control', 'shift', 'se', ['ctrl'], [], '400,300,700,460'],
        ['control', 'shift', 'e', ['ctrl', 'shift'], [], '400,300,700,400'],
        ['control', 'shift', 'se', ['shift'], ['ctrl'], '300,240,800,520'],
        ['alt', 'super', 'se', [], ['alt'], '300,240,800,520'],
        ['alt', 'super', 'se', [], ['super'], '400,300,700,467'],
        ['alt', 'super', 'se', [], ['alt', 'super'], '300,234,800,533'],
        ['alt', 'super', 'se', [], ['ctrl'], '400,300,700,460'],
        ['alt', 'super', 'se', [], ['shift'], '400,300,1520,900'],
        ['disabled', 'disabled', 'se', [], ['ctrl'], '400,300,700,460'],
        ['disabled', 'disabled', 'se', [], ['shift'], '400,300,1520,900'],
        ['shift', 'shift', 'se', [], ['shift'], '300,234,800,533'],
    ];
    globalThis.symmetricResizeE2E = {done: false, lines: []};
    (async () => {
        for (let i = 0; i < 10; i++) {
            pointer.notify_absolute_motion(now(), 100 + i, 100);
            await sleep(100);
        }
        for (const [center, aspect, handle, first, second, expected] of cases) {
            settings.set_string('center-modifier', center);
            settings.set_string('aspect-modifier', aspect);
            const [held, final] = await drag(handle, first, second);
            const ok = held === expected && final === expected;
            symmetricResizeE2E.lines.push((ok ? 'PASS' : 'FAIL') + ' center=' + center + ' aspect=' + aspect + ' ' + handle + ' [' + first + ']->[' + second + '] expected ' + expected + ' held ' + held + ' final ' + final);
        }
        global.display.disconnect(grabSignal);
        const fresh = grabActors.size === cases.length;
        symmetricResizeE2E.lines.push((fresh ? 'PASS' : 'FAIL') + ' every resize uses a fresh grab actor (' + grabActors.size + '/' + cases.length + ')');
    })().catch(e => symmetricResizeE2E.lines.push('FAIL ' + e)).finally(() => symmetricResizeE2E.done = true);
    return true;
})()
EOF
)" >/dev/null

for _ in $(seq 600); do
    [ "$(evaluate 'symmetricResizeE2E.done')" = true ] && break
    sleep 0.5
done
lines=$(evaluate "symmetricResizeE2E.lines.join('|')")
lines=${lines#\"}
printf '%s\n' "${lines%\"}" | tr '|' '\n'
if [[ $lines == *FAIL* ]] || [[ $lines != *PASS* ]]; then
    tail -20 "$SYMMETRIC_RESIZE_E2E/shell.log" >&2
    exit 1
fi
echo "All tests passed."
