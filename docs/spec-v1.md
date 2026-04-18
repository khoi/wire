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

wire app list [--include-accessory]
wire app ls [--include-accessory]
wire app launch <app> [--open <path-or-url> ...] [--wait] [--focus]
wire app quit <app> [--force]
wire app quit --pid <pid> [--force]

wire inspect [--app <app>]
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

- default lists regular foreground applications
- `--include-accessory` also includes accessory apps such as helpers and menu bar apps

### `app launch <app>`

Launches the app by name or path. `--bundle-id` can target the app by bundle identifier instead.

- `--open <path-or-url>` repeats and passes documents or URLs right after launch
- `--wait` waits until the app reports it finished launching
- `--focus` brings the app to the foreground after launch

### `app quit <app>`

Quits running applications.

- `--pid <pid>` targets a running app by process identifier instead of name
- app names match exactly, case-insensitive
- matching multiple running apps by name quits all of them
- `--force` uses force termination instead of a normal quit request

### `inspect [--app <app>]`

Inspects the active UI and returns a fresh snapshot with short element refs such as `@e1`, `@e2`.

- with no arguments, inspects the frontmost app
- `--app <app>` targets a running app by exact case-insensitive name
- captures one visible window only
- returns a saved screenshot path for that window
- never activates or focuses the target app

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

`@eN` is a short alias minted by `wire` during `inspect`.

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

Agents should prefer `@eN` after `inspect`.

## Example Flows

Open Google Chrome when already running:

```bash
wire app launch chrome --open https://google.com --focus
```

Open Google Chrome when not running:

```bash
wire app launch chrome --open https://google.com --focus
```

The behavior is the same:

- if Chrome is running, `app launch` reuses the app process
- if Chrome is not running, `app launch` starts it
- `--focus` brings Chrome to the foreground
- `--open` passes the target to Chrome

Inspect and act:

```bash
wire inspect
wire click @e1
wire type "weather london"
wire press enter
```

Example `inspect` result:

```json
{
  "snapshot": "s7",
  "data": {
    "app": {
      "name": "Google Chrome",
      "bundleId": "com.google.Chrome",
      "pid": 83304,
      "focused": true
    },
    "imagePath": "/tmp/wire/2f7.../snapshots/s7/image.png",
    "elements": [
      {
        "id": "@e1",
        "role": "text-field",
        "name": "Search",
        "enabled": true
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
