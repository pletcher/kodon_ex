# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kodon is an Elixir static site generator for scholarly editions of ancient texts. It powers the [AHCIP (A Homeric Commentary in Progress)](https://github.com/new-alexandria-foundation/ahcip) project, producing a static HTML reading environment for Homer's Iliad, Odyssey, and the Homeric Hymns. The system merges scholar translations with prose fallback translations (Butler/Power/Nagy for Iliad/Odyssey, Evelyn-White for Hymns) and supports scholarly commentary.

## Commands

```bash
# Install dependencies
mix deps.get

# Run all tests
mix test

# Run a single test file
mix test test/kodon/parser_test.exs

# Run a specific test by line number
mix test test/kodon/parser_test.exs:42

# Build the static site
mix kodon.build

# Start dev server (default port 4000)
mix kodon.server
mix kodon.server 8080   # custom port

# Extract comments from a PostgreSQL dump
mix kodon.extract_comments <dump_file> <output_file>
```

## Architecture

### Data Pipeline

The build pipeline flows: **source files → parse → merge with fallback → render HTML**.

1. **Parser** (`lib/kodon/parser.ex`) — Parses scholar translation `.txt` files into `%Book{}` structs. Handles multiple format variants (single-line, line-per-verse, tab-separated). Extracts inline annotations: Greek glosses (macron marker `>`), notes `[n:...]`, variant readings `[n:v.l. ...]`, cross-references `[=I-1.372]`, and editorial markers `[[...]]`.

2. **TEIParser** (`lib/kodon/tei_parser.ex`) — Parses TEI XML for fallback (prose) translations using Erlang's `:xmerl`. Two formats: `:book_card_milestone` (Iliad/Odyssey with `<milestone unit="line">`) and `:line_elements` (Hymns with `<l n="N">`).

3. **ButlerFallback** (`lib/kodon/butler_fallback.ex`) — Detects gaps in scholar translations and fills them with fallback prose. Outputs a mixed list of `{:scholar_line, %Line{}}` and `{:butler_gap, %{start_line, end_line, butler_text}}` items.

4. **Renderer** (`lib/kodon/renderer.ex`) — Renders parsed data to HTML using compile-time EEx templates from `priv/templates/`. Handles inline annotation popovers, smart quotes, macron conversion (`e>` → `ē`), DraftJS content, and cross-reference links.

### Key Domain Modules

- **WorkRegistry** (`lib/kodon/work_registry.ex`) — Central registry of all works (Iliad, Odyssey, 33 Hymns) with CTS URNs, slugs, TEI paths, and section metadata. The single source of truth for what gets built.
- **Kodon** (`lib/kodon.ex`) — Maps scholar translation filenames to Iliad book numbers (12 of 24 books have scholar translations).
- **CommentaryParser** (`lib/kodon/commentary_parser.ex`) — Parses per-author markdown files with YAML front-matter keyed by CTS URN.
- **CrossRef** (`lib/kodon/cross_ref.ex`) — Generates links between passages using `I-BOOK.LINE` format.

### Data Structures

- `%Kodon.Book{}` — number, title, preamble, translators, lines, work_slug
- `%Kodon.Line{}` — number, sort_key (tuple `{integer, suffix}` for ordering "40a", "302 v.l."), text, raw_text, annotations
- `%Kodon.Annotation{}` — type atom (`:greek_gloss`, `:note`, `:variant`, `:cross_ref`, `:editorial`), content, raw

### Configuration

All config is under the `:kodon` app key, set by the consuming application:
- `:site_title` — displayed in layout header and `<title>` tags (default: `"Kodon"`)
- `:output_dir` — where generated HTML goes (default: `"output"`)
- `:commentary_dir` — where commentary markdown lives (default: `"commentary"`)
- `:templates_dir` — optional override for EEx templates (default: `priv/templates/`)

## Conventions

- Comprehensive `@type`, `@spec`, `@moduledoc`, and `@doc` annotations on all modules
- Structs for all domain models; atoms for type discriminators (`:scholar_line`, `:butler_gap`, etc.)
- Fail-fast with `File.read!()` / `File.write!()`; `Mix.raise()` for fatal task errors
- Tests use `async: true` where possible; fixtures in `test/fixtures/`
- Dependencies: `earmark` (Markdown), `jason` (JSON), `:xmerl` (XML, Erlang built-in)
