## ebump
`ebump` is a script to manage erlang package versions. `ebump` stores the version in `ebump.config` file.

## Features
- `ebump` follows (SemVer) spec
- Allows cycling through `alpha`, `beta`, `rc` pre-releases.
- Automatically adds a count and `git commit hash` to the package version as build metadata

## Build
```
$ rebar3 escriptize
```

## Usage
```
Usage: ebump [-c <config>] reset|current|major|minor|patch|pre

  -c, --config  /path/to/config/file

```
