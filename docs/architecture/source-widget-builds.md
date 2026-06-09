# Source-Based Widget Builds

WidgetDesk widgets still run as local files in `WKWebView`. The host loads the path declared by `widget.json` and grants read access to the widget directory, so the build boundary can stay in `WidgetDeskCore` without changing the macOS window host.

## Current Shape

Simple widgets can continue to ship a hand-written `index.html`.

Complex widgets can use a source layout:

```text
widgets/<id>/
  widget.json
  source/
    main.js
    style.css
  vendor/
    optional-local-library.js
  dist/
    index.html
```

The tool agent exposes `build_component`. It requires `source/main.js`, generates `dist/index.html`, and updates `widget.json` so `entry` points to `dist/index.html`.

This gives the LLM a cleaner target for larger JavaScript widgets, including Three.js-style scenes, without asking it to paste everything into one HTML file.

## Dependency Policy

The exploratory implementation does not run npm or install packages. Network dependencies are intentionally rejected by validation.

Allowed:

- Relative imports from local widget files.
- Local files under `source/`, `dist/`, or `vendor/`.
- A future curated vendor bundle shipped by WidgetDesk.

Rejected:

- CDN scripts, styles, fonts, images, and module imports.
- Package manager installs inside the agent loop.
- Arbitrary `package.json` dependency resolution.

## Next Step

If package support is needed, add it as a controlled build capability:

- Use an allowlist of package names and versions.
- Install into a cache owned by WidgetDesk, not each widget.
- Disable lifecycle scripts.
- Require build output in `dist/`.
- Keep validation as the final success condition.
