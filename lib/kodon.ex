defmodule Kodon do
  @moduledoc """
  Static site generator library for scholarly editions of ancient texts.

  Kodon provides parsing and rendering infrastructure for TEI XML texts
  and scholar translation files. Consuming applications (like AHCIP)
  handle orchestration, work registries, and build tasks.

  ## Core modules

  - `Kodon.TEIParser` — SAX-based TEI XML parser
  - `Kodon.Parser` — Scholar translation `.txt` file parser
  - `Kodon.Renderer` — HTML rendering with recursive element templates
  - `Kodon.CrossRef` — Cross-reference parsing and link generation
  - `Kodon.CommentaryParser` — Commentary markdown file parser
  """
end
