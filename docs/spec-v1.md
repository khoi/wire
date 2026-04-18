# wire v1

`wire` is a JSON-first CLI for agent-friendly background computer use on macOS, with a global `--plain` mode for human-readable stdout.

## Goals

- Generic macOS control, not a browser-specific CLI
- Friendly surface area, not raw Accessibility API by default
- Short ephemeral element refs for action loops
- Stable machine-readable output on every command

## Non-goals

- No top-level `browser`
- No generic `tab` model
- No public raw AX surface in v1
- No backwards compatibility constraints

## Command Shape

```text
wire [--plain] [--verbose|-v] permissions grant
wire [--plain] [--verbose|-v] permissions status

wire app list
wire app ls
wire app launch <app> [--open <path-or-url> ...] [--wait] [--focus]
wire app quit <app>

wire open <target> [--app <app>]

wire see [--app <app>]
wire click <@eN|query>
wire type <text> [--into <@eN|query>]
wire press <key|combo>
wire scroll [<@eN|query>] --up <n>|--down <n>

wire screenshot [path]
```

## Command Semantics

### `permissions grant`

Guides the user through required macOS permissions.

v1 covers exactly:

- `accessibility`
- `screen-recording`

`grant` prompts only for missing permissions, then re-checks final state. It exits non-zero if either permission is still missing after the prompt pass.

### `permissions status`

Returns current permission and runtime status.

v1 covers exactly:

- `accessibility`
- `screen-recording`

### `app list`

Lists running applications.

### `app launch <app>`

Launches the app by name or path. `--bundle-id` can target the app by bundle identifier instead.

- `--open <path-or-url>` repeats and passes documents or URLs right after launch
- `--wait` waits until the app reports it finished launching
- `--focus` brings the app to the foreground after launch

### `app quit <app>`

Quits the app.

### `open <target> [--app <app>]`

Opens a URL, file, or app-supported target. If `--app` is set, `wire` uses that app, focusing it if running and launching it if not.

### `see [--app <app>]`

Inspects the active UI and returns a fresh snapshot with short element refs such as `@e1`, `@e2`.

### `click <@eN|query>`

Clicks an element by short ref from the latest snapshot or by a friendly query.

### `type <text> [--into <@eN|query>]`

Types text into the focused field, or into a matched element when `--into` is provided.

### `press <key|combo>`

Sends a key or shortcut such as `enter`, `escape`, `cmd+l`.

### `scroll [<@eN|query>] --up <n>|--down <n>`

Scrolls the focused area or a matched element.

### `screenshot [path]`

Captures a screenshot and returns the saved path.

## Output Contract

Default mode writes exactly one JSON object to stdout.

- `stdout`: JSON by default, human-readable text with `--plain`
- `stderr`: diagnostics only, including `--verbose` logs
- `exit 0`: success
- `exit != 0`: failure

Base success shape:

```json
{
  "snapshot": "s7",
  "data": {}
}
```

Base error shape:

```json
{
  "error": {
    "code": "stale_ref",
    "message": "@e1 is no longer valid"
  }
}
```

## Element Refs

`@eN` is a short alias minted by `wire` during `see`.

- Snapshot-scoped, not global
- Stored in `wire` session state
- Resolved back to a live element before each action
- Returns `stale_ref` if the UI moved and the element no longer matches

`wire` should store a resolver payload, not just a raw pointer:

- app identity
- process identity
- window identity
- ancestry or path data
- role, name, value
- geometry

Public UX uses short refs and friendly queries. Raw accessibility details stay internal in v1.

## Queries

Queries stay human and agent friendly:

- `"Search"`
- `button:"Save"`
- `text-field:"Search"`

Agents should prefer `@eN` after `see`.

## Example Flows

Open Google Chrome when already running:

```bash
wire app launch chrome --focus
wire open https://google.com --app chrome
```

Open Google Chrome when not running:

```bash
wire app launch chrome --focus
wire open https://google.com --app chrome
```

The behavior is the same:

- if Chrome is running, `app launch` starts or reuses the app process
- `--focus` brings Chrome to the foreground
- open the target in Chrome

Inspect and act:

```bash
wire see
wire click @e1
wire type "weather london"
wire press enter
```

Example `see` result:

```json
{
  "snapshot": "s7",
  "data": {
    "app": {
      "id": "@a1",
      "name": "Google Chrome",
      "focused": true
    },
    "elements": [
      {
        "id": "@e1",
        "role": "text-field",
        "name": "Search"
      },
      {
        "id": "@e2",
        "role": "button",
        "name": "Google Search"
      }
    ]
  }
}
```

## Design Notes

- Keep the public API generic and small
- Make JSON the default, not an option
- Prefer short refs over full accessibility identifiers
- Hide raw accessibility concepts unless they are required for debugging
