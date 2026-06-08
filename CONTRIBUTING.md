# Contributing

Thanks for helping make WidgetDesk better. The project is still early, so small focused changes are easiest to review and merge.

## Good First Contributions

- Improve README wording or screenshots
- Add tests around `WidgetDeskCore`
- Polish a built-in widget template
- Report rough edges in the macOS host
- Help package and sign a downloadable `.app`

## Local Checks

Run the Swift package checks before opening a PR:

```bash
cd apps/macos-host
swift build
swift test
```

## Pull Request Guidelines

- Keep PRs focused on one behavior, bug, or documentation improvement.
- Include screenshots or screen recordings for visible UI changes.
- Avoid committing local files, generated build output, API keys, or personal widget data.
- Update README or docs when a user-facing workflow changes.
- Add or update tests when changing `WidgetDeskCore` behavior.

## Project Shape

The main app lives in `apps/macos-host`.

- `WidgetDeskCore`: shared data model, store, settings, templates, and agent logic
- `WidgetDeskHost`: native macOS host app
- `widgetdesk`: developer CLI
- `widgetdesk-agent`: offline prompt-to-template CLI
