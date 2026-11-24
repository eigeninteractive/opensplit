# Contributing to OpenSplit

[Open an issue](https://github.com/eigeninteractive/opensplit/issues/new/choose)
for bugs and feature requests. For split or rounding bugs, include the
currency, exact amounts and expected result. Use example data so your report
can be shared publicly.

## Set up and test

Follow the [local development runbook](docs/runbook.md#testing-a-branch-locally)
for the toolchain, local Worker, Android and browser setup, and test commands.
The Worker runs locally with its own data.

Format Dart with `dart format lib test tool` and run `dart analyze --fatal-infos`.
For TypeScript, HTML, CSS, JSON and other files covered by Biome, run
`pnpm format` from `server/` and review the diff. Run the suites relevant to
your change, including the Chrome suites for browser storage or money logic.

## Find the right place for a change

| Area                                  | Where to start                                                                             |
| ------------------------------------- | ------------------------------------------------------------------------------------------ |
| Split calculations and balance math   | [Domain code](lib/domain/), [automatic splits](docs/automatic-splits.md)                   |
| Local data and migrations             | [Local database](docs/local-database.md)                                                   |
| Sync, Worker and generated API client | [Architecture and contract](docs/architecture.md#the-contract-and-how-types-reach-the-app) |
| App UI and artwork                    | [UI guidelines](docs/ui-ux.md), [brand guide](docs/brand/README.md)                        |
| Public website and project funding    | [Static site](site/), [funding maintenance](docs/funding-setup.md)                         |
| Deployments and release requirements  | [Runbook](docs/runbook.md#every-release), [versions](docs/runbook.md#versions)             |

Include the checks you ran in your pull request. For changes to the app,
follow the [version and release notes checklist](docs/runbook.md#in-every-pull-request).
