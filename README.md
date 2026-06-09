# MCP Server for Enterprise Architect — native **Windows ARM64** repackage

Build a **native Windows on ARM64** installer for Sparx Systems' *MCP Server for Enterprise
Architect* from the official x86/x64 release.

> [!IMPORTANT]
> **All credit for the actual product goes to Sparx Systems.** This repository contains **no
> Sparx binaries** — only build tooling that re-targets the official installer you download
> yourself. The original *MCP Server for Enterprise Architect* is created and distributed by
> **Sparx Systems Japan**: <https://www.sparxsystems.jp/en/MCP/>

---

## How it works

![Architecture diagram: the AI client spawns the MCP server (MCP3.exe) over stdio; the server bridges to the MCP_EA.dll add-in inside Enterprise Architect over a named pipe; the add-in reaches the EA Repository via in-process COM](docs/architecture.png)

The AI client (Claude Desktop, Claude Code, …) **starts the MCP server itself** — it spawns
`MCP3.exe` as a child process and speaks MCP over stdio. The server then connects over a **named
pipe** to the `MCP_EA.dll` add-in running *inside* Enterprise Architect, which reaches the live model
through in-process **COM**. Because that bridge is a named pipe, the **native ARM64 server works with
the (emulated x86) EA add-in unchanged**.

> Diagram source (editable): [`docs/architecture.excalidraw`](docs/architecture.excalidraw) — open it
> at [excalidraw.com](https://excalidraw.com). The PNG above is exported from it.

---

## Why this exists

Sparx ships the MCP server only as **x86** (`Intel`) and **x64** MSIs. On Windows on ARM neither
installs/runs natively:

- the MSI `Template` is hard-coded to `Intel`/`x64`, which Windows Installer uses to gate install
  eligibility;
- the launcher `MCP3.exe` is a **native x86/x64 .NET apphost**;
- the installer's `.NET 9` runtime check is a **native x64 custom-action DLL** that cannot load
  during an ARM64 install.

The good news from reverse-engineering the MSI: **only the packaging is CPU-specific.** The product
is a framework-dependent **.NET 9** app whose code is fully portable:

- `MCP3.dll` (the server), `MCP_EA.dll` (the EA add-in) and **all** dependencies are **AnyCPU/IL**;
- the server talks to AI clients over **stdio** and to Enterprise Architect over a **named pipe** —
  it never calls EA's COM directly — so a **native ARM64 server happily drives an emulated x64/x86
  EA add-in**.

```
AI client ──stdio──► MCP3.exe (.NET 9 server) ──named pipe──► MCP_EA.dll add-in (inside EA) ──COM──► EA Repository
```

So the only thing that needs to change for native ARM64 is: a native **arm64 apphost**, an **Arm64
MSI**, fixed **add-in registration**, and dropping the native runtime-check. That is exactly what
`build.ps1` does.

## What the build produces / changes

| | Official x64 MSI | This ARM64 MSI |
|---|---|---|
| MSI `Template` | `x64` | **`Arm64`** |
| `MCP3.exe` | native x64 apphost | **native arm64 apphost** |
| Managed payload (`MCP3.dll`, `MCP_EA.dll`, deps) | AnyCPU | **reused byte-for-byte** |
| EA add-in registration | `EAAddins64` (64-bit view) | **`EAAddins` + `EAAddins64` in both 32- and 64-bit views** |
| .NET runtime check | native x64 custom action | removed (the apphost prompts if the runtime is missing) |

The add-in is registered for **both 32-bit and 64-bit Enterprise Architect**. EA reads its add-in
keys from the registry view matching its *own* architecture, so registering in both views means the
add-in shows up whether you run 32-bit EA (`EA400`) or 64-bit EA (`EA64`) under emulation.

## Prerequisites

- **Windows on ARM64** (to install/run the result; you can *build* on any Windows + .NET SDK).
- **.NET SDK 9.0+** — <https://dotnet.microsoft.com/download/dotnet/9.0> (the arm64 build also needs
  the **.NET 9 arm64 *runtime*** at install/run time; the apphost will prompt with a download link if
  it's missing).
- **The official Sparx MSI** — download from <https://www.sparxsystems.jp/en/MCP/> (the **x64** MSI
  is recommended; the x86 one also works since the managed payload is identical).
- WiX is **not** a manual prerequisite — it's pinned as a local `dotnet` tool
  (`.config/dotnet-tools.json`) and restored automatically by the build.

## Build

```powershell
git clone https://github.com/klesajos/<this-repo>.git
cd <this-repo>
.\build.ps1 -SourceMsi "$HOME\Downloads\MCP_EA_x64.msi"
```

Output: `dist\MCP_EA_arm64.msi`. The script auto-detects the product version, add-in ProgID, CLSID
and assembly identity from *your* MSI, so it should keep working for future Sparx releases.

## Install

```powershell
msiexec /i dist\MCP_EA_arm64.msi
```

Then:

1. Open **Enterprise Architect** with a project, go to **Specialize ▸ Add-Ins ▸ Manage Add-Ins**,
   and confirm **MCPAddin** appears. Tick **Load on Startup**.
2. Point your MCP client at the installed server. Example for **Claude Desktop**
   (`%APPDATA%\Claude\claude_desktop_config.json`):

   ```json
   {
     "mcpServers": {
       "enterprise-architect": {
         "command": "C:\\Program Files\\Sparx Systems\\EA\\MCP_Server\\MCP3.exe"
       }
     }
   }
   ```

   Fully quit and reopen the client. With EA running, the server's tools become available.

## How it works (internals)

`build.ps1`:

1. **Administrative-extracts** your Sparx MSI (`msiexec /a`) — no system changes — to harvest the
   managed payload.
2. **Mints a native arm64 apphost** by building the tiny `apphost/MCP3.csproj` with
   `-r win-arm64`, keeping only the produced `MCP3.exe`. A framework-dependent apphost has no hash
   binding to its managed DLL, so this launcher drives Sparx's unmodified `MCP3.dll`.
3. **Assembles the payload**: Sparx's managed binaries + the arm64 apphost.
4. **Builds the MSI** from `src/MCP_EA_arm64.wxs` with WiX (`-arch arm64`), injecting the
   auto-detected version/ProgID/CLSID/assembly values.

## Repository layout

```
build.ps1                     # one-shot build script (start here)
src/MCP_EA_arm64.wxs          # WiX authoring for the ARM64 MSI
apphost/                      # throwaway project that mints the arm64 MCP3.exe apphost
.config/dotnet-tools.json     # pins WiX as a local dotnet tool
```

## Notes & caveats

- The produced MSI is **unsigned** — it cannot carry Sparx's original signature. Windows SmartScreen
  may warn on first run. Build it yourself / use at your own discretion.
- This is an **independent, unofficial** repackage for interoperability on ARM64. It is **not
  affiliated with or endorsed by Sparx Systems.** Please support Sparx and obtain the product from
  them: <https://www.sparxsystems.jp/en/MCP/>
- Trademarks (Sparx Systems, Enterprise Architect) belong to their respective owners.

## License

Build tooling in this repo: **MIT** (see [LICENSE](LICENSE)). The MIT license covers *only* this
tooling — **not** the Sparx product, which it neither contains nor relicenses.
