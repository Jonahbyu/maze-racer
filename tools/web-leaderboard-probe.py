"""Drive the LIVE maze-racer page in headless Chrome and exercise the
leaderboard bridge.

This is the only instrument that answers "can the hosted game actually reach
Firebase" -- the harnesses are headless with REST disabled, and curl against the
same endpoints proves the service, not the page. CLAUDE.md records exactly this
gap for the silent-audio bug.

Headless so it never opens a window on the user's screen.
"""
import json
import subprocess
import time
import urllib.request

import websocket

CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
URL = "https://jonahbyu.github.io/maze-racer/"
PORT = 9333


def start_chrome():
    return subprocess.Popen(
        [CHROME, "--headless=new", f"--remote-debugging-port={PORT}",
         "--no-first-run", "--no-default-browser-check",
         "--user-data-dir=" + r"C:\Users\Jonah\AppData\Local\Temp\claude\cdpprofile",
         "--disable-gpu", "--remote-allow-origins=*", URL],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def page_ws(timeout=30):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            tabs = json.load(urllib.request.urlopen(
                f"http://127.0.0.1:{PORT}/json", timeout=3))
            for t in tabs:
                if t.get("type") == "page" and "maze-racer" in t.get("url", ""):
                    return t["webSocketDebuggerUrl"]
        except Exception:
            pass
        time.sleep(1)
    return None


class CDP:
    def __init__(self, ws_url):
        self.ws = websocket.create_connection(ws_url, timeout=60)
        self.n = 0

    def eval(self, expr, await_promise=False):
        self.n += 1
        self.ws.send(json.dumps({
            "id": self.n, "method": "Runtime.evaluate",
            "params": {"expression": expr, "returnByValue": True,
                       "awaitPromise": await_promise},
        }))
        while True:
            msg = json.loads(self.ws.recv())
            if msg.get("id") == self.n:
                r = msg.get("result", {})
                if "exceptionDetails" in r:
                    return {"__error": str(r["exceptionDetails"])[:200]}
                return r.get("result", {}).get("value")


def main():
    proc = start_chrome()
    try:
        ws_url = page_ws()
        if not ws_url:
            print("FAILED: no page target")
            return
        cdp = CDP(ws_url)

        # The engine needs time to download (~43MB pack) and boot.
        print("waiting for the bridge...")
        status = None
        for i in range(90):
            time.sleep(2)
            has = cdp.eval("typeof window.mazeRacerLB !== 'undefined'")
            if has is True:
                status = cdp.eval("window.mazeRacerLB.status()")
                if status:
                    try:
                        d = json.loads(status)
                        if d.get("ready"):
                            break
                    except Exception:
                        pass
        print("bridge status :", status)

        if not status:
            print("FAILED: bridge never appeared")
            return
        d = json.loads(status)
        if not d.get("ready"):
            print("FAILED: never signed in. error =", d.get("error"))
            return
        print("signed in     : uid", str(d.get("uid"))[:12] + "...")

        # Name and post, exactly as the game does.
        cdp.eval("window.mazeRacerLB.setName('browser-probe')")
        time.sleep(1)
        seed = int(time.time()) & 0x7FFFFFFF
        payload = json.dumps({
            "score": 222333, "time": 265.0, "seed": seed,
            "board": "general", "mazes": 5, "died": False,
        })
        ok = cdp.eval(
            "window.mazeRacerLB.postScore(%s)" % json.dumps(payload))
        print("post accepted :", ok)

        for _ in range(15):
            time.sleep(1)
            st = cdp.eval("window.mazeRacerLB.postState()")
            if st and st != "pending":
                break
        print("post state    :", st)

        # Read the board back through the page itself.
        cdp.eval("window.mazeRacerLB.fetchBoard('general','score',10)")
        rows = None
        for _ in range(15):
            time.sleep(1)
            raw = cdp.eval("window.mazeRacerLB.boardResult()")
            if raw:
                rows = json.loads(raw)
                break
        if rows and rows.get("ok"):
            print("board rows    :", len(rows.get("rows", [])))
            for r in rows.get("rows", [])[:5]:
                print("   ", r.get("name"), r.get("score"), int(r.get("time", 0)))
        else:
            print("board         :", rows)

        good = st == "ok" and rows and rows.get("ok")
        print("\nRESULT:", "PASS" if good else "FAIL")
    finally:
        proc.terminate()


main()
