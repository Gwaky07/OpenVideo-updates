# START HERE

This is the ASCII-safe copy of `先看这里.md`. Same product, same steps.

OpenVideo is a local workbench, not a public website. After unzipping, double-click `OpenVideo.cmd`. It opens a page on **your** computer. Materials, Jianying drafts, and model keys stay on that machine.

## You must bring

1. Windows 10 or 11
2. Internet (first launch installs the runtime and pinned upstreams)
3. Your own LLM gateway (Base URL + API Key + text/vision/JSON models)
4. Jianying Professional already installed on this PC
5. Your own material folder

Without model, Jianying, and materials, the page can open, but the creation chain cannot finish. This package does **not** contain someone else's keys, materials, projects, or Jianying catalog.

## First use

1. Unzip the ZIP completely. Do not run it from inside the archive.
2. Double-click `OpenVideo.cmd` and keep that window open. The first run may take more than ten minutes. Missing Node / Python 3.12 / Git are installed automatically when possible.
3. When the workbench opens, open **系统设置** on the left and fill in your own model gateway.
4. Create a project and authorize your own material folder with the Windows folder dialog. Confirm read-only.
5. Follow the pages: 创作要求 → 分镜 → AI 剪辑 → preview MP4 → Jianying draft.

Later, just double-click `OpenVideo.cmd` again. For a desktop icon, run `Create-OpenVideoShortcut.cmd` once.

## Updates

The current `v0.3.5` channel supports whole-product updates. The sidebar can
replace the packaged Web UI, Gateway, launcher and `OpenVideo.cmd` together.
Projects, materials, model settings, Jianying identity and the private Catalog
stay in the user's local data directory.

After changing code in the private source repository, push `main` and run the
publisher on the developer machine:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Publish-OpenVideoFullUpdateQuiet.ps1 -Version v0.3.5
```

The publisher builds the current Web app, rebuilds the portable launcher,
scans the ZIP, writes its SHA-256 manifest and pushes only the ZIP, `latest.json`
and this guide to the public `OpenVideo-updates` feed. Users do not log in to
GitHub. They open their local workbench, click the sidebar update button and
let it restart. A failed health check restores the previous program version.

Give a new user the complete `OpenVideo-v0.3.5-windows.zip` first. Unzip it
fully and start `OpenVideo.cmd` once before using the update button. Do not run
the button from a source checkout containing `.git`.

## Do not

- Copy another computer's `OpenVideo.lnk`, `%LOCALAPPDATA%\OpenVideo`, or API Key
- Commit materials, keys, Jianying identity, or the runtime directory
- Expect a finished video without a configured model

More detail: `README-WINDOWS.md`.
