import Adw from 'gi://Adw';
import Gtk from 'gi://Gtk';
import {ExtensionPreferences} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

const KEYS = ['disabled', 'shift', 'control', 'alt', 'super'];

export default class extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const settings = this.getSettings(), page = new Adw.PreferencesPage(), group = new Adw.PreferencesGroup({title: 'Modifier Keys'});
        for (const [key, title] of [['center-modifier', 'Resize From Center'], ['aspect-modifier', 'Keep Aspect Ratio']]) {
            const row = new Adw.ComboRow({title, model: Gtk.StringList.new(['Disabled', 'Shift', 'Ctrl', 'Alt', 'Super']), selected: KEYS.indexOf(settings.get_string(key))});
            row.connect('notify::selected', () => settings.set_string(key, KEYS[row.selected]));
            group.add(row);
        }
        page.add(group);
        window.set_default_size(460, 280);
        window.add(page);
    }
}
