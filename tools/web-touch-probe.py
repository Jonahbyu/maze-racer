"""Drive the BUILT maze-racer page in headless Chrome with a real touch tap and
count how many turns one tap produces.

This is the only instrument that answers the question the phantom-input bug
actually poses. The harnesses construct an InputEventScreenTouch by hand and
feed it straight to _on_pad_input, which proves the handler's logic and says
nothing about what a browser on a phone really delivers -- and what it delivers
is the point: Godot's emulate_mouse_from_touch synthesizes a mouse event from
every touch, so one tap arrives twice. CLAUDE.md records the identical gap for
the silent-audio bug, where every local check passed against a hosted build that
made no sound.

CDP's Input.dispatchTouchEvent plus Emulation.setEmitTouchEventsForMouse is what
makes Chrome present itself as a touch device, so the engine takes the touch
path rather than the desktop mouse path.

Usage:
    python tools/web-touch-probe.py [url]

Defaults to the local build directory served over http, since the point is to
check a change BEFORE it ships. Pass the live URL to check production.

Headless, so it never opens a window.
"""
import http.server
import json
import os
import subprocess
import sys
import threading
import time
import urllib.request

import websocket

CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
PORT = 9334
HTTP_PORT = 8777
PROFILE = r"C:\Users\Jonah\AppData\Local\Temp\claude\cdptouchprofile"


def serve(directory):
    """Serve the build locally. The web export needs a real http origin --
    file:// fails on the wasm fetch."""
    handler = lambda *a, **k: http.server.SimpleHTTPRequestHandler(
        *a, directory=directory, **k)
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", HTTP_PORT), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


def start_chrome(url):
    return subprocess.Popen(
        [CHROME, "--headless=new", f"--remote-debugging-port={PORT}",
         "--no-first-run", "--no-default-browser-check",
         "--user-data-dir=" + PROFILE,
         "--disable-gpu", "--remote-allow-origins=*",
         # A phone-shaped window, because every pad size is derived from the
         # shorter screen edge (CLAUDE.md section 9d).
         "--window-size=844,390",
         url],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def page_ws(timeout=40):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            tabs = json.load(urllib.request.urlopen(
                f"http://127.0.0.1:{PORT}/json", timeout=3))
            for t in tabs:
                if t.get("type") == "page" and t.get("url", "").startswith(
                        ("http://", "https://")):
                    return t["webSocketDebuggerUrl"]
        except Exception:
            pass
        time.sleep(1)
    return None


class CDP:
    def __init__(self, ws_url):
        self.ws = websocket.create_connection(ws_url, timeout=60)
        self.n = 0

    def send(self, method, params=None):
        self.n += 1
        mine = self.n
        self.ws.send(json.dumps({
            "id": mine, "method": method, "params": params or {}}))
        while True:
            msg = json.loads(self.ws.recv())
            if msg.get("id") == mine:
                return msg.get("result", {})

    def eval(self, expr, await_promise=False):
        r = self.send("Runtime.evaluate", {
            "expression": expr, "returnByValue": True,
            "awaitPromise": await_promise})
        if "exceptionDetails" in r:
            return {"__error": str(r["exceptionDetails"])[:300]}
        return r.get("result", {}).get("value")

    def touch(self, x, y, pressed):
        """A real finger, as a touchscreen delivers it."""
        return self.send("Input.dispatchTouchEvent", {
            "type": "touchStart" if pressed else "touchEnd",
            "touchPoints": ([{"x": x, "y": y}] if pressed else []),
        })


def main():
    url = sys.argv[1] if len(sys.argv) > 1 else None
    httpd = None
    if url is None:
        root = os.path.join(os.path.dirname(os.path.dirname(
            os.path.abspath(__file__))), "build", "web")
        if not os.path.isfile(os.path.join(root, "index.html")):
            print("FAILED: no local build at", root)
            print("        export one first, or pass a URL")
            return 1
        httpd = serve(root)
        url = f"http://127.0.0.1:{HTTP_PORT}/index.html"
    print("url           :", url)

    proc = start_chrome(url)
    try:
        ws_url = page_ws()
        if not ws_url:
            print("FAILED: no page target")
            return 1
        cdp = CDP(ws_url)
        cdp.send("Runtime.enable")
        cdp.send("Input.enable")
        # Present as a touch device, so the engine takes the touch path.
        cdp.send("Emulation.setTouchEmulationEnabled",
                 {"enabled": True, "maxTouchPoints": 5})
        cdp.send("Emulation.setEmitTouchEventsForMouse",
                 {"enabled": True, "configuration": "mobile"})

        print("waiting for the engine to boot...")
        booted = False
        for _ in range(90):
            time.sleep(2)
            ready = cdp.eval(
                "(function(){var c=document.querySelector('canvas');"
                "return !!c && c.width>0;})()")
            if ready is True:
                booted = True
                break
        if not booted:
            print("FAILED: engine never booted")
            return 1
        print("engine booted : yes")
        # The canvas exists well before the menu is interactive.
        time.sleep(8)

        size = cdp.eval(
            "(function(){var c=document.querySelector('canvas');"
            "return c.clientWidth+'x'+c.clientHeight;})()")
        print("canvas        :", size)

        # THE MEASUREMENT.
        #
        # Godot exposes no turn counter to JS, so the count itself is asserted
        # in ShellTest. What only a browser can show is the DELIVERY: that one
        # finger produces both a touchstart and a synthesized mousedown on the
        # canvas, which is the mechanism behind the double turn. Counting the
        # DOM events the engine receives is the closest observable proxy, and it
        # is a real one -- if a tap raises only one pointer event here, the
        # premise of the bug is wrong and the fix is aimed at nothing.
        #
        # Listen on WINDOW, not on the canvas. Measured: a dispatched touch
        # raises touchstart on window and document but NOT on the canvas
        # element, so a canvas-only listener counts zero and the probe reports
        # itself inconclusive while the events are in fact flowing.
        cdp.eval("""
            window.__probeErrors = [];
            window.addEventListener('error', function(e){
                window.__probeErrors.push(String(e.message));
            });
            window.__ev = {touchstart:0, mousedown:0, touchend:0, mouseup:0};
            // Timestamps too: the fix is a 250ms echo window, so the GAP
            // between a touch and its synthesized mouse twin is what decides
            // whether that window is wide enough. A count alone cannot say.
            window.__t = [];
            ['touchstart','mousedown','touchend','mouseup'].forEach(function(n){
                window.addEventListener(n, function(){
                    window.__ev[n]++;
                    window.__t.push(n + '@' + Math.round(performance.now()));
                }, true);
            });
        """)

        # Tap where the left steering pad sits: hard against the left margin,
        # above the HUD's bottom band.
        rect = cdp.eval(
            "(function(){var r=document.querySelector('canvas')"
            ".getBoundingClientRect();"
            "return [r.x,r.y,r.width,r.height].join(',');})()")
        rx, ry, rw, rh = [float(v) for v in str(rect).split(",")]
        x, y = int(rx + rw * 0.12), int(ry + rh * 0.62)
        print("tap point     : %d,%d" % (x, y))

        cdp.touch(x, y, True)
        time.sleep(0.12)
        cdp.touch(x, y, False)
        time.sleep(1.0)

        ev = cdp.eval("window.__ev") or {}
        order = cdp.eval("window.__t.join(' ')")
        print("event order   : %s" % order)
        errs = cdp.eval("window.__probeErrors")
        alive = cdp.eval(
            "(function(){var c=document.querySelector('canvas');"
            "return !!c && c.width>0;})()")

        print("events for ONE tap:")
        for k in ("touchstart", "mousedown", "touchend", "mouseup"):
            print("  %-11s: %s" % (k, ev.get(k)))
        print("page errors   :", errs if errs else "none")
        print("still running :", alive)
        print("")

        touches = int(ev.get("touchstart") or 0)
        mice = int(ev.get("mousedown") or 0)

        if touches == 0:
            print("INCONCLUSIVE: the tap raised no touchstart at all, so touch")
            print("  emulation is not reaching the canvas and this probe is")
            print("  measuring nothing. Fix the probe before trusting a PASS.")
            return 1

        if mice >= 1:
            print("CONFIRMED: ONE finger delivered %d touchstart and %d"
                  % (touches, mice))
            print("  mousedown. That is the double delivery the phantom-input")
            print("  bug rides on: the browser synthesizes a mouse event from")
            print("  the touch, Godot turns each into an InputEvent, and a pad")
            print("  handler that accepts both fires TWICE for one tap.")
            print("  TouchControls drops a mouse event landing within")
            print("  ECHO_WINDOW_MS of a touch on the same pad.")
        else:
            print("NOTE: no synthesized mousedown observed. Godot ALSO does this")
            print("  internally (emulate_mouse_from_touch), on an InputEvent")
            print("  that never appears in the DOM -- so this is not an all")
            print("  clear. ShellTest is the assertion that matters.")

        ok = (not errs) and alive is True
        print("")
        print("RESULT:", "PASS" if ok else "FAIL")
        print("  (PASS here means the page survived a real touch. The turn")
        print("   COUNT is ShellTest's assertion, not this tool's.)")
        return 0 if ok else 1
    finally:
        proc.terminate()
        if httpd:
            httpd.shutdown()


if __name__ == "__main__":
    sys.exit(main())
