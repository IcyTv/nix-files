"""Exercise the Nix-built plugin in an isolated OpenCode TUI; no model/API key needed."""

import argparse
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import signal
import struct
import subprocess
import tempfile
import termios
import time


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("plugin", type=Path, help="Nix output containing tui.js")
parser.add_argument("--opencode", default="opencode")
parser.add_argument("--output-dir", type=Path, default=Path(tempfile.gettempdir()))
args = parser.parse_args()
plugin = args.plugin.resolve()
root = Path(tempfile.mkdtemp(prefix="opencode-latex-", dir=args.output_dir))
for name in ("config/opencode", "cache", "data", "state", "home", "work", "probe"):
    (root / name).mkdir(parents=True, exist_ok=True)

# The probe calls the actual plugin setup and exercises its registered renderer,
# rather than substituting a standalone MathJax render for a plugin integration test.
probe = r'''
import { Plugin } from "@opencode/plugin/tui"
import { writeFile } from "node:fs/promises"

const outputRoot = ARTIFACT_ROOT

export default Plugin.define({
  id: "test.latex-graphics",
  async setup(context) {
    const images = []
    let cleanup
    try {
      const { default: latex } = await import(PLUGIN_ENTRY)
      let renderBlock
      cleanup = await latex.setup({
        ...context,
        options: { graphicsMode: "kitty" },
        markdown: {
          ...context.markdown,
          registerCodeBlockRenderer(language, render) {
            if (language !== "latex") throw new Error(`Unexpected language: ${language}`)
            renderBlock = render
            return () => {}
          },
        },
      })
      if (!renderBlock) throw new Error("LaTeX renderer not registered")
      const results = []
      const formulas = [
        String.raw`\frac{-b \pm \sqrt{b^2 - 4ac}}{2a}`,
        String.raw`\begin{aligned} E &= mc^2 \\ A &= \begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix} \end{aligned}`,
      ]
      for (const [index, text] of formulas.entries()) {
        const renderable = renderBlock({ text }, {
          defaultRender() { throw new Error("Plugin fell back to source renderer") },
        })
        images.push(renderable)
        context.renderer.root.add(renderable)
        const graphical = await renderable.whenGraphicsReady()
        if (renderable.graphicsError) throw renderable.graphicsError
        const image = renderable.image
        if (!graphical || !image || image.png.length < 100 || image.png[0] !== 137 || image.png[1] !== 80) {
          throw new Error("Missing graphical MathJax PNG")
        }
        await writeFile(`${outputRoot}/equation-${index}.png`, image.png)
        results.push({ pngBytes: image.png.length, width: image.width, height: image.height })
      }
      await writeFile(`${outputRoot}/result.json`, JSON.stringify({ success: true, results }))
    } catch (error) {
      await writeFile(`${outputRoot}/result.json`, JSON.stringify({ success: false, error: String(error), stack: error?.stack }))
      throw error
    }
    return () => { cleanup?.(); images.forEach(image => image.destroy()) }
  },
})
'''
probe = probe.replace("PLUGIN_ENTRY", json.dumps(str(plugin / "tui.js")))
probe = probe.replace("ARTIFACT_ROOT", json.dumps(str(root)))
(root / "probe/tui.ts").write_text(probe)
(root / "probe/index.ts").write_text(
    'import { Plugin } from "@opencode/plugin";\n'
    'export default Plugin.define({ id: "test.latex-graphics.server", setup() {} });\n'
)
(root / "probe/package.json").write_text(json.dumps({
    "name": "latex-graphics-probe", "type": "module",
    "exports": {".": "./index.ts", "./tui": "./tui.ts"},
}))
(root / "config/opencode/opencode.json").write_text(json.dumps({
    "plugins": [str(plugin), str(root / "probe")], "update": "disable",
}))
env = {key: value for key, value in os.environ.items() if not key.startswith("OPENCODE_")}
env.update({
    "HOME": str(root / "home"),
    "XDG_CONFIG_HOME": str(root / "config"),
    "XDG_CACHE_HOME": str(root / "cache"),
    "XDG_DATA_HOME": str(root / "data"),
    "XDG_STATE_HOME": str(root / "state"),
    "TERM": "xterm-kitty",
})
master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 960, 640))
try:
    process = subprocess.Popen(
        [args.opencode, "--standalone", "--log-level", "debug"],
        cwd=root / "work", env=env, stdin=slave, stdout=slave, stderr=slave,
        start_new_session=True,
    )
finally:
    os.close(slave)
output = bytearray()
result = root / "result.json"
try:
    deadline = time.monotonic() + 40
    while time.monotonic() < deadline and process.poll() is None:
        ready, _, _ = select.select([master], [], [], 0.2)
        if ready:
            try:
                chunk = os.read(master, 65536)
            except OSError:
                break
            output.extend(chunk)
            if b"\x1b[6n" in chunk:
                os.write(master, b"\x1b[1;1R")
        if result.exists():
            break
finally:
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
    os.close(master)
    (root / "terminal.log").write_bytes(output)

print(f"Test artifacts: {root}")
if not result.exists():
    raise SystemExit("No probe result; inspect terminal.log and data/opencode/log/opencode.log")
report = json.loads(result.read_text())
print(json.dumps(report, indent=2))
logs = (root / "data/opencode/log/opencode.log").read_text()
if not report.get("success") or "plugin operation failed" in logs:
    raise SystemExit(1)
