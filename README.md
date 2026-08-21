# Chutney Lab

Chutney Lab is a browser-based workspace for writing and linting Cucumber Gherkin with the real [Chutney](https://www.usechutney.com/) Ruby gem.

It provides:

- live Chutney diagnostics with rule names and exact line/column locations;
- syntax highlighting and inline error-line highlighting;
- persistent create, open, edit and save workflows;
- `.feature` upload and download;
- responsive desktop and mobile layouts;
- keyboard shortcuts: `Cmd/Ctrl-S` to save and `Cmd/Ctrl-Enter` to lint.

## Setup

Requires Ruby 3.2+ (the project currently targets Ruby 4.0.1), SQLite, and a modern browser.

```sh
bundle install
bin/rails db:prepare
bin/dev
```

Open <http://localhost:3000>.

## Tests

```sh
bin/rails test
bin/rails test:system
```

The system suite uses headless Chrome through Selenium.

## Architecture

`ChutneyAnalyser` writes submitted content to an isolated temporary `.feature` file, runs Chutney in-process, and normalizes its structured findings for the editor. Feature files are stored in SQLite through `FeatureFile`. A Stimulus controller implements the layered syntax editor, live lint requests, persistence, uploads, downloads, and clickable issue navigation.
