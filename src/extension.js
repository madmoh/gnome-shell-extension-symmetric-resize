import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

export default class extends Extension {
    enable() {
        this.g = this.getSettings();
        this.b = global.display.connect('grab-op-begin', (d, w, op) => {
            if (!(op & 0xf000) || op & 0x100) return;
            const r = w.get_frame_rect(), [px, py] = global.get_pointer();
            const c = this.g.get_enum('center-modifier'), a = this.g.get_enum('aspect-modifier');
            const ex = !!(op & 0x2000) - !!(op & 0x1000), ey = !!(op & 0x4000) - !!(op & 0x8000);
            this.d = false;
            this.f = (x, y, m) => {
                const k = m & c ? 2 : 1;
                let W = r.width + ex * (x - px) * k, H = r.height + ey * (y - py) * k;
                if (m & a) {
                    const s = Math.max(ex && W / r.width, ey && H / r.height);
                    [W, H] = [r.width * s, r.height * s];
                }
                const fx = m & c || !ex ? .5 : (1 - ex) / 2, fy = m & c || !ey ? .5 : (1 - ey) / 2;
                [W, H] = [Math.max(1, Math.round(W)), Math.max(1, Math.round(H))];
                w.move_resize_frame(true, Math.round(r.x + fx * (r.width - W)), Math.round(r.y + fy * (r.height - H)), W, H);
            };
            global.stage.get_grab_actor().connect('captured-event', (_, e) => {
                const m = e.get_state() & (c | a);
                if (e.type() !== 3 || !this.f || !m && !this.d) return false;
                this.d = !!m;
                this.f(...e.get_coords(), m);
                return true;
            });
        });
        this.e = global.display.connect('grab-op-end', () => {
            if (this.d) this.f?.(...global.get_pointer());
            this.f = null;
        });
    }
    disable() {
        global.display.disconnect(this.b);
        global.display.disconnect(this.e);
        this.f = this.g = null;
    }
}
