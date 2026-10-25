---
name: extract-pen-screens
description: Use when implementing or updating a Lengua screen to match the design/lengua-ios.pen file — exports the exact screen frame to a PNG reference image and dumps its precise specs (text, colors, fonts, sizes, spacing, design tokens) so the SwiftUI implementation is pixel-accurate.
---

# Extract Pen Screens

## Overview

`design/lengua-ios.pen` is a pen.dev design file holding the canonical designs
for the app's screens. This skill turns a screen in that file into two things an
implementer needs: a **reference PNG** committed under `design/images/` and an
**exact spec dump** (text, colors, fonts, sizes, spacing) so nothing is guessed.

You interact with the `.pen` file **only** through the `mcp__pencil__*` MCP tools
— never `Read`/`Grep` (the file is encrypted and binary). The workhorse is
`mcp__pencil__execute`, which runs a small JS snippet against the file.

## Critical: always pass `filePath`

The pencil app may have a *different* `.pen` file open as its active canvas
(check with `mcp__pencil__get_app_state`). **Every** `execute` / `browser` call
must pass `filePath` explicitly, or you will read/modify the wrong document:

```
filePath: "<repo>/design/lengua-ios.pen"
```

## The `.pen` layout (project-specific)

The document root is **decomposed**, not one frame per screen:

- A style-guide section at the top: `Guide Header`, `Foundations`, `Typography`,
  `Components Showcase`, `Interaction States`, plus stray component fragments
  (`Segment …`, `Language Card …`, `Tab …`, `Vocabulary …`). **Ignore these.**
- Each **app screen** is three sibling top-level frames stacked vertically:
  `Status Bar` (393×30) + `<Name> Content` (393×740, or `Session Header` +
  `Session Content` for session screens) + `Main Tab Bar` (393×82).
- App frames are **393pt wide** (iPhone). Filter on that to skip the style guide.

The `<Name> Content` frame is the part you implement; the Status Bar and Main Tab
Bar are shared chrome. Some screens have **multiple** Content frames — these are
different **states** of the same screen (e.g. two `Look Up Content` frames =
recording state vs. translating state). Export and implement all states.

### Design frame → code page

| Design content frame        | Code (`Lengua/Views/Pages/`) |
|-----------------------------|------------------------------|
| `Look Up Content` (×2)      | `TranslatePage.swift`        |
| `Library Content`           | `LibraryPage.swift`          |
| `Review Content`            | `ReviewPage.swift`           |
| `Talk Content`              | `TalkPage.swift`             |
| `You Content`               | `YouPage.swift`              |
| `Sign In Content`           | `SignInPage.swift`           |
| `Session Content` (×4)      | `ReviewSession.swift` / session states |

Names drift as designs evolve — confirm against the live enumeration each time.

## Workflow

1. **Enumerate** the top-level frames to find the target and its node id(s):

   ```js
   Get((n,c)=>{ if(c.depth!==1){ if(c.depth>1)c.skipChildren(); return; }
     Print(n.id,"|",n.type,"|",Math.round(c.bounds.width)+"x"+Math.round(c.bounds.height),"|",JSON.stringify(n.name)); })
   ```

2. **Look** at each target state to understand it (inline, no files written):

   ```js
   TakeScreenshot(["<id1>","<id2>"])   // one per state; screenshots are expensive
   ```

3. **Export** the target frames to committed PNGs. `Export` writes
   `<nodeId>.png` (2× scale) into the given directory:

   ```js
   Export(["<id1>","<id2>"], "png", "<repo>/design/images")
   ```

   Rename the files to something legible (e.g. `translate-recording.png`).

4. **Dump exact specs** — resolve tokens and component instances so every value
   is literal. Print a compact row per node (id, name, type, key visual props):

   ```js
   Print(GetVariables())   // design tokens: colors, fonts, numbers
   Get("<id>", (n,c)=>Print(c.depth, n.type, JSON.stringify(n.name),
     n.content??"", n.fill??"", n.fontSize??"", n.fontFamily??"", n.fontWeight??"",
     "gap="+(n.gap??""), "pad="+JSON.stringify(n.padding??""),
     Math.round(c.bounds.width)+"x"+Math.round(c.bounds.height)),
     {resolveVariables:true, resolveInstances:true})
   ```

   Pull colors/gaps/radii/font sizes straight from this — do not eyeball them
   from the PNG. For SVG glyphs use `{includePathGeometry:true}`.

5. **Implement** in SwiftUI to match exactly. This is Swift in a Point-Free
   codebase, so **invoke the relevant `pfw-*` skills first** (`pfw-observable-models`,
   `pfw-modern-swiftui`, `pfw-testing`, etc. — see the repo `CLAUDE.md`). Keep the
   Model as the source of all text/state and the View visual-only (repo `CLAUDE.md`
   Model/View split). Update the existing page, don't create a parallel one.

## Common mistakes

- **Forgetting `filePath`** → you silently operate on whatever file the app has
  open. Always pass it.
- **Treating a Content frame as the whole screen** → it excludes the shared
  Status Bar / Main Tab Bar chrome; those are separate frames.
- **Missing a state** → a screen with N Content frames has N states; implement
  each. Grep the enumeration for duplicate names.
- **Eyeballing values from the PNG** → use the `Get` spec dump with
  `resolveVariables:true`; the PNG is for layout/feel, the dump is for numbers.
- **Reading the `.pen` with `Read`/`Grep`** → it is encrypted; use the pencil MCP
  tools only.
- **Hardcoding strings in the View** → per repo `CLAUDE.md`, all display text
  lives on the Model.
