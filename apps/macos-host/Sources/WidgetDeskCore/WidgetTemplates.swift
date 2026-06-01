import Foundation

public struct WidgetDraft: Equatable, Sendable {
    public var manifest: WidgetManifest
    public var html: String

    public init(manifest: WidgetManifest, html: String) {
        self.manifest = manifest
        self.html = html
    }
}

public enum WidgetTemplate: String, CaseIterable, Sendable {
    case sampleClock = "sample-clock"
    case clock
    case pomodoro
    case systemStats = "system-stats"
    case memo
    case tapCounter = "tap-counter"

    public var displayName: String {
        switch self {
        case .sampleClock, .clock:
            return "Clock"
        case .pomodoro:
            return "Pomodoro"
        case .systemStats:
            return "System Stats"
        case .memo:
            return "Memo"
        case .tapCounter:
            return "Tap Counter"
        }
    }

    public func draft(id: String, prompt: String, anchor: WidgetAnchor? = nil) -> WidgetDraft {
        switch self {
        case .sampleClock, .clock:
            return WidgetDraft(
                manifest: WidgetManifest(
                    id: id,
                    name: id == "sample-clock" ? "Sample Clock" : "Clock",
                    x: 40,
                    y: 90,
                    width: 320,
                    height: 150,
                    interactive: false,
                    anchor: anchor ?? .bottomRight
                ),
                html: Self.clockHTML(title: id == "sample-clock" ? "WidgetDesk Host" : "WidgetDesk")
            )
        case .pomodoro:
            return WidgetDraft(
                manifest: WidgetManifest(
                    id: id,
                    name: "Pomodoro",
                    x: 40,
                    y: 90,
                    width: 300,
                    height: 172,
                    interactive: true,
                    anchor: anchor ?? .bottomLeft
                ),
                html: Self.pomodoroHTML
            )
        case .systemStats:
            return WidgetDraft(
                manifest: WidgetManifest(
                    id: id,
                    name: "System Stats",
                    x: 40,
                    y: 90,
                    width: 320,
                    height: 168,
                    interactive: false,
                    anchor: anchor ?? .topRight
                ),
                html: Self.systemStatsHTML
            )
        case .memo:
            return WidgetDraft(
                manifest: WidgetManifest(
                    id: id,
                    name: "Memo",
                    x: 40,
                    y: 90,
                    width: 320,
                    height: 180,
                    interactive: true,
                    anchor: anchor ?? .topCenter
                ),
                html: Self.memoHTML(prompt: prompt)
            )
        case .tapCounter:
            return WidgetDraft(
                manifest: WidgetManifest(
                    id: id,
                    name: "Tap Counter",
                    x: 40,
                    y: 90,
                    width: 230,
                    height: 150,
                    interactive: true,
                    anchor: anchor ?? .bottomRight
                ),
                html: Self.tapCounterHTML
            )
        }
    }

    public static func template(named name: String) throws -> WidgetTemplate {
        if let template = WidgetTemplate(rawValue: name) {
            return template
        }
        if name == "system" || name == "stats" {
            return .systemStats
        }
        if name == "counter" || name == "tap" {
            return .tapCounter
        }
        throw WidgetDeskError.unknownTemplate(name)
    }
}

private extension WidgetTemplate {
    static func clockHTML(title: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            :root { color-scheme: dark; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif; }
            html, body { width: 100%; height: 100%; margin: 0; overflow: hidden; background: transparent; user-select: none; }
            .clock { box-sizing: border-box; width: 100%; height: 100%; padding: 18px 20px; border: 1px solid rgba(255,255,255,.12); border-radius: 18px; background: rgba(8,12,20,.72); box-shadow: 0 14px 40px rgba(0,0,0,.35); -webkit-backdrop-filter: blur(24px); backdrop-filter: blur(24px); color: rgba(255,255,255,.92); text-align: right; }
            .time { font-size: 56px; font-weight: 220; line-height: 1; letter-spacing: 0; }
            .seconds { margin-left: 6px; font-size: 28px; opacity: .48; }
            .date { margin-top: 8px; font-size: 14px; opacity: .66; }
          </style>
        </head>
        <body>
          <main class="clock" aria-label="WidgetDesk clock">
            <div class="time"><span id="hm">--:--</span><span class="seconds" id="s">:--</span></div>
            <div class="date" id="date">\(title.htmlEscaped)</div>
          </main>
          <script>
            const hm = document.getElementById("hm");
            const s = document.getElementById("s");
            const date = document.getElementById("date");
            const formatter = new Intl.DateTimeFormat(undefined, { year: "numeric", month: "short", day: "numeric", weekday: "short" });
            function tick() {
              const now = new Date();
              hm.textContent = now.toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit", hour12: false });
              s.textContent = ":" + String(now.getSeconds()).padStart(2, "0");
              date.textContent = formatter.format(now);
            }
            tick();
            setInterval(tick, 1000);
          </script>
        </body>
        </html>
        """
    }

    static let pomodoroHTML = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        :root { color-scheme: dark; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif; }
        html, body { width: 100%; height: 100%; margin: 0; overflow: hidden; background: transparent; user-select: none; }
        .panel { box-sizing: border-box; width: 100%; height: 100%; padding: 18px; border-radius: 18px; background: rgba(19,24,31,.78); border: 1px solid rgba(255,255,255,.12); color: white; -webkit-backdrop-filter: blur(24px); backdrop-filter: blur(24px); }
        .row { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
        .label { font-size: 13px; opacity: .64; text-transform: uppercase; letter-spacing: .08em; }
        .time { margin-top: 8px; font-size: 52px; font-weight: 240; line-height: 1; letter-spacing: 0; }
        button { width: 42px; height: 34px; border: 0; border-radius: 10px; background: rgba(255,255,255,.14); color: white; font-size: 16px; }
        .buttons { display: flex; gap: 8px; }
      </style>
    </head>
    <body>
      <main class="panel">
        <div class="row">
          <div class="label" id="mode">Focus</div>
          <div class="buttons"><button id="toggle">▶</button><button id="reset">↺</button></div>
        </div>
        <div class="time" id="time">25:00</div>
      </main>
      <script>
        let seconds = 25 * 60;
        let running = false;
        const time = document.getElementById("time");
        const toggle = document.getElementById("toggle");
        const reset = document.getElementById("reset");
        function render() {
          const m = String(Math.floor(seconds / 60)).padStart(2, "0");
          const s = String(seconds % 60).padStart(2, "0");
          time.textContent = m + ":" + s;
          toggle.textContent = running ? "Ⅱ" : "▶";
        }
        toggle.onclick = () => { running = !running; render(); };
        reset.onclick = () => { running = false; seconds = 25 * 60; render(); };
        setInterval(() => { if (running && seconds > 0) { seconds -= 1; render(); } }, 1000);
        render();
      </script>
    </body>
    </html>
    """

    static let systemStatsHTML = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        :root { color-scheme: dark; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; }
        html, body { width: 100%; height: 100%; margin: 0; overflow: hidden; background: transparent; user-select: none; }
        .panel { box-sizing: border-box; width: 100%; height: 100%; padding: 16px 18px; border-radius: 16px; background: rgba(11,18,24,.76); border: 1px solid rgba(255,255,255,.12); color: white; -webkit-backdrop-filter: blur(22px); backdrop-filter: blur(22px); }
        .title { font-size: 13px; opacity: .64; margin-bottom: 12px; }
        .metric { margin: 10px 0; }
        .row { display: flex; justify-content: space-between; font-size: 13px; }
        .bar { height: 7px; margin-top: 6px; border-radius: 999px; background: rgba(255,255,255,.12); overflow: hidden; }
        .fill { height: 100%; width: 50%; border-radius: inherit; background: linear-gradient(90deg, #52d273, #45aaf2); }
      </style>
    </head>
    <body>
      <main class="panel">
        <div class="title">System pulse</div>
        <section class="metric"><div class="row"><span>CPU</span><span id="cpu">--%</span></div><div class="bar"><div class="fill" id="cpuBar"></div></div></section>
        <section class="metric"><div class="row"><span>Memory</span><span id="mem">--%</span></div><div class="bar"><div class="fill" id="memBar"></div></div></section>
        <section class="metric"><div class="row"><span>Battery</span><span id="bat">--%</span></div><div class="bar"><div class="fill" id="batBar"></div></div></section>
      </main>
      <script>
        const ids = ["cpu", "mem", "bat"];
        function set(id, value) {
          document.getElementById(id).textContent = value + "%";
          document.getElementById(id + "Bar").style.width = value + "%";
        }
        function tick() {
          set("cpu", 18 + Math.floor(Math.random() * 54));
          set("mem", 42 + Math.floor(Math.random() * 28));
          navigator.getBattery?.().then(b => set("bat", Math.round(b.level * 100))).catch(() => set("bat", 100));
        }
        tick();
        setInterval(tick, 2500);
      </script>
    </body>
    </html>
    """

    static func memoHTML(prompt: String) -> String {
        let cleaned = prompt
            .replacingOccurrences(of: "create", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "add", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "memo", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "note", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let text = cleaned.isEmpty ? "New note" : cleaned
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            :root { color-scheme: light; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; }
            html, body { width: 100%; height: 100%; margin: 0; overflow: hidden; background: transparent; }
            textarea { box-sizing: border-box; width: 100%; height: 100%; resize: none; border: 1px solid rgba(20,20,20,.12); border-radius: 16px; padding: 16px; color: #1d1d1f; background: rgba(255,248,180,.88); box-shadow: 0 14px 36px rgba(0,0,0,.20); font: 17px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; outline: none; }
          </style>
        </head>
        <body>
          <textarea id="memo" spellcheck="false">\(text.htmlEscaped)</textarea>
          <script>
            const key = "widgetdesk.memo." + location.pathname;
            const memo = document.getElementById("memo");
            memo.value = localStorage.getItem(key) || memo.value;
            memo.addEventListener("input", () => localStorage.setItem(key, memo.value));
          </script>
        </body>
        </html>
        """
    }

    static let tapCounterHTML = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        :root { color-scheme: dark; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif; }
        html, body { width: 100%; height: 100%; margin: 0; overflow: hidden; background: transparent; user-select: none; }
        button { width: 100%; height: 100%; border: 0; border-radius: 18px; background: rgba(22,28,36,.78); color: white; box-shadow: 0 14px 36px rgba(0,0,0,.25); -webkit-backdrop-filter: blur(22px); backdrop-filter: blur(22px); }
        .count { display: block; font-size: 58px; font-weight: 260; line-height: 1; letter-spacing: 0; }
        .label { display: block; margin-top: 8px; font-size: 13px; opacity: .58; }
      </style>
    </head>
    <body>
      <button id="tap"><span class="count" id="count">0</span><span class="label">tap counter</span></button>
      <script>
        const key = "widgetdesk.tap-counter." + location.pathname;
        const count = document.getElementById("count");
        let value = Number(localStorage.getItem(key) || 0);
        function render() { count.textContent = value; localStorage.setItem(key, value); }
        document.getElementById("tap").onclick = () => { value += 1; render(); };
        render();
      </script>
    </body>
    </html>
    """
}

private extension String {
    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
