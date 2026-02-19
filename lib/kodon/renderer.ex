defmodule Kodon.Renderer do
  @moduledoc """
  Renders parsed book data and TEI elements into HTML using EEx templates.

  Provides two rendering layers:

  1. **Page rendering** — `render_layout/2`, `render_index/2`, `render_section/7`
     evaluate page-level EEx templates (layout, index, book, nav).

  2. **Element rendering** — `render_element/1`, `render_children/1` recursively
     render `%TEIParser.Element{}` and `%TEIParser.TextRun{}` structs using
     per-element EEx templates from `priv/templates/elements/`.

  ## Template resolution

  Templates are resolved with a three-level fallback:

  1. Custom `:templates_dir` (set by consuming app)
  2. Kodon default (`priv/templates/`)
  3. `elements/default.eex` (catch-all for unknown elements)
  """

  require EEx

  alias Kodon.{CrossRef, Annotation, CommentaryParser}
  alias Kodon.TEIParser.{Element, TextRun}

  @priv_dir Path.join([__DIR__, "..", "..", "priv"]) |> Path.expand()

  EEx.function_from_file(
    :def,
    :popover,
    Path.join([@priv_dir, "templates", "components", "popover.eex"]),
    [
      :assigns
    ]
  )

  # --- Element rendering ---

  @doc """
  Render a TEI element or text run to HTML.

  For `%TextRun{}` structs, returns the HTML-escaped text.
  For `%Element{}` structs, recursively renders children and evaluates
  the element's EEx template.
  """
  @spec render_element(Element.t() | TextRun.t()) :: String.t()
  def render_element(%TextRun{text: text}) do
    template_path = resolve_template_path(Path.join("elements", "text_run.eex"))
    EEx.eval_file(template_path, assigns: [text: escape_html(text), element: nil, children: nil])
  end

  def render_element(%Element{} = el) do
    children_html = render_children(el.children)
    template_path = resolve_template_path(Path.join("elements", "#{el.tagname}.eex"))
    EEx.eval_file(template_path, assigns: [element: el, children: children_html, text: nil])
  end

  @doc """
  Render a list of TEI element children to a single HTML string.
  """
  @spec render_children([Element.t() | TextRun.t()]) :: String.t()
  def render_children(children) when is_list(children) do
    Enum.map_join(children, &render_element/1)
  end

  # --- Template resolution ---

  @doc """
  Resolve a template path with three-level fallback.

  Checks in order:
  1. Custom `:templates_dir` from app config
  2. Kodon's default `priv/templates/`
  3. `elements/default.eex` as catch-all
  """
  @spec resolve_template_path(String.t()) :: String.t()
  def resolve_template_path(relative) do
    custom_dir = Application.get_env(:kodon, :templates_dir)

    cond do
      custom_dir && File.exists?(Path.join(custom_dir, relative)) ->
        Path.join(custom_dir, relative)

      File.exists?(default_template(relative)) ->
        default_template(relative)

      true ->
        default_template(Path.join("elements", "default.eex"))
    end
  end

  defp default_template(relative) do
    Application.app_dir(:kodon, Path.join("priv", Path.join("templates", relative)))
  end

  # --- Page rendering ---

  @doc """
  Render the index page.
  """
  @spec render_index([map()], [map()]) :: String.t()
  def render_index(nav_groups, work_groups) do
    nav =
      EEx.eval_file(
        resolve_template_path("nav.eex"),
        assigns: [nav_groups: nav_groups]
      )

    site_title = Application.get_env(:kodon, :site_title, "Kodon")

    content =
      EEx.eval_file(
        resolve_template_path("index.eex"),
        assigns: [nav: nav, work_groups: work_groups, site_title: site_title]
      )

    render_layout("Home", content)
  end

  @doc """
  Render a single section page.
  """
  @spec render_section(map(), list(), [map()], list(), String.t(), String.t(), map(), String.t()) ::
          String.t()
  def render_section(
        book,
        content,
        nav_groups,
        comments,
        display_title,
        attribution,
        greek_lines \\ %{},
        scaife_url \\ ""
      ) do
    nav =
      EEx.eval_file(
        resolve_template_path("nav.eex"),
        assigns: [nav_groups: nav_groups]
      )

    book_content =
      EEx.eval_file(
        resolve_template_path("book.eex"),
        assigns: [
          nav: nav,
          display_title: display_title,
          preamble: book.preamble,
          translators: book.translators,
          content: content,
          book_number: book.number,
          comments: comments,
          fallback_attribution: attribution,
          greek_lines: greek_lines,
          work_slug: Map.get(book, :work_slug, ""),
          scaife_url: scaife_url
        ]
      )

    render_layout(display_title, book_content)
  end

  defp render_layout(title, content) do
    site_title = Application.get_env(:kodon, :site_title, "Kodon")
    url_prefix = Application.get_env(:kodon, :url_prefix, "")

    EEx.eval_file(
      resolve_template_path("layout.eex"),
      assigns: [title: title, content: content, site_title: site_title, url_prefix: url_prefix]
    )
  end

  # --- Commentary loading ---

  @doc """
  Load all comments from commentary directory, grouped by work and section.
  Returns %{"work:section" => [comment, ...]} sorted by start_line.
  """
  @spec load_all_comments(String.t()) :: map()
  def load_all_comments(commentary_dir) do
    if File.dir?(commentary_dir) do
      CommentaryParser.load(commentary_dir)
      |> Enum.group_by(fn c -> "#{c["work"]}:#{c["book"]}" end)
      |> Enum.into(%{}, fn {key, comments} ->
        {key, Enum.sort_by(comments, & &1["start_line"])}
      end)
    else
      %{}
    end
  end

  # --- Line rendering ---

  @doc """
  Render a line's text with inline Greek glosses styled and annotation popovers.
  """
  @spec render_line_text(map(), term()) :: String.t()
  def render_line_text(line, _book_number) do
    text = smartquotes(line.text)

    # Style Greek glosses inline
    glosses =
      line.annotations
      |> Enum.filter(&(&1.type == :greek_gloss))
      |> Enum.map(& &1.content)

    text =
      Enum.reduce(glosses, text, fn gloss, acc ->
        String.replace(acc, gloss, ~s(<span class="greek-gloss">[#{escape_html(gloss)}]</span>),
          global: false
        )
      end)

    # Add cross-ref links
    cross_refs =
      line.annotations
      |> Enum.filter(&(&1.type == :cross_ref))

    ref_links =
      cross_refs
      |> Enum.flat_map(& &1.refs)
      |> Enum.map(&CrossRef.render_link/1)

    text =
      if length(ref_links) > 0 do
        text <> ~s( <span class="cross-refs">[) <> Enum.join(ref_links, ", ") <> "]</span>"
      else
        text
      end

    # Add inline annotation popovers for notes, variants, and editorial markers
    inline_annotations =
      line.annotations
      |> Enum.filter(&(&1.type in [:note, :variant, :editorial]))
      |> Enum.with_index(1)

    popover_html =
      Enum.map(inline_annotations, fn {ann, idx} ->
        superscript = integer_to_superscript(idx)
        type_label = note_type_label(ann.type)
        content = render_annotation_content(ann)

        popover(superscript: superscript, type_label: type_label, content: content)
      end)
      |> Enum.join("")

    macronize(text) <> popover_html
  end

  defp integer_to_superscript(n) do
    superscripts = %{
      ?0 => "\u2070",
      ?1 => "\u00B9",
      ?2 => "\u00B2",
      ?3 => "\u00B3",
      ?4 => "\u2074",
      ?5 => "\u2075",
      ?6 => "\u2076",
      ?7 => "\u2077",
      ?8 => "\u2078",
      ?9 => "\u2079"
    }

    n
    |> Integer.to_string()
    |> String.to_charlist()
    |> Enum.map(&Map.get(superscripts, &1, &1))
    |> List.to_string()
  end

  @doc """
  Return a display label for an annotation type.
  """
  @spec note_type_label(atom()) :: String.t()
  def note_type_label(:note), do: "Note"
  def note_type_label(:variant), do: "Variant"
  def note_type_label(:editorial), do: "Editorial"
  def note_type_label(_), do: "Note"

  @doc """
  Render the content of an annotation for display in the commentary.
  """
  @spec render_annotation_content(Annotation.t()) :: String.t()
  def render_annotation_content(%Annotation{type: :variant, content: content}) do
    ~s(<em>v.l.</em> #{escape_html(content)})
  end

  def render_annotation_content(%Annotation{content: content, refs: refs}) when refs != [] do
    ref_links =
      refs
      |> Enum.map(&CrossRef.render_link/1)
      |> Enum.join(", ")

    escape_html(content) <> " " <> ref_links
  end

  def render_annotation_content(%Annotation{content: content}) do
    escape_html(content)
  end

  # --- DraftJS rendering ---

  @doc """
  Render DraftJS JSON content to HTML.
  """
  @spec render_draftjs(map()) :: String.t()
  def render_draftjs(%{"blocks" => blocks, "entityMap" => entity_map}) do
    blocks
    |> Enum.map(&render_draftjs_block(&1, entity_map))
    |> Enum.join("\n")
  end

  defp render_draftjs_block(%{"text" => text, "type" => type} = block, entity_map) do
    inline_styles = Map.get(block, "inlineStyleRanges", [])
    entity_ranges = Map.get(block, "entityRanges", [])

    rendered_text = apply_draftjs_formatting(text, inline_styles, entity_ranges, entity_map)

    case type do
      "blockquote" -> "<blockquote>#{rendered_text}</blockquote>"
      "header-two" -> "<h4>#{rendered_text}</h4>"
      _ -> "<p>#{rendered_text}</p>"
    end
  end

  defp apply_draftjs_formatting(text, inline_styles, entity_ranges, entity_map) do
    chars = String.graphemes(text)
    len = length(chars)

    if len == 0 do
      ""
    else
      # Build per-character style/entity tags
      {opens, closes} = build_formatting_tags(len, inline_styles, entity_ranges, entity_map)

      chars
      |> Enum.with_index()
      |> Enum.map(fn {char, i} ->
        open_tags = Map.get(opens, i, "")
        close_tags = Map.get(closes, i, "")
        open_tags <> escape_html(char) <> close_tags
      end)
      |> Enum.join()
    end
  end

  defp build_formatting_tags(len, inline_styles, entity_ranges, entity_map) do
    # Collect all ranges with their open/close tags
    ranges =
      Enum.map(inline_styles, fn %{"offset" => offset, "length" => length, "style" => style} ->
        tag = style_to_tag(style)
        {offset, offset + length, tag}
      end) ++
        Enum.flat_map(entity_ranges, fn %{"offset" => offset, "length" => length, "key" => key} ->
          entity = Map.get(entity_map, to_string(key), %{})
          entity_to_tags(entity, offset, length)
        end)

    # Build maps of open/close tags per character index
    Enum.reduce(ranges, {%{}, %{}}, fn {start, stop, {open, close}}, {opens, closes} ->
      stop = min(stop, len)
      start = min(start, len - 1)

      opens = Map.update(opens, start, open, &(&1 <> open))
      closes = Map.update(closes, stop - 1, close, &(close <> &1))
      {opens, closes}
    end)
  end

  defp style_to_tag("ITALIC"), do: {"<em>", "</em>"}
  defp style_to_tag("BOLD"), do: {"<strong>", "</strong>"}
  defp style_to_tag("UNDERLINE"), do: {"<u>", "</u>"}
  defp style_to_tag(_), do: {"", ""}

  defp entity_to_tags(%{"type" => "LINK", "data" => %{"url" => url}}, offset, length) do
    [{offset, offset + length, {~s(<a href="#{escape_html(url)}">), "</a>"}}]
  end

  defp entity_to_tags(%{"type" => "IMAGE", "data" => data}, offset, length) do
    src = escape_html(data["src"] || "")
    alt = escape_html(data["alt"] || "")
    [{offset, offset + length, {~s(<img src="#{src}" alt="#{alt}" loading="lazy">), ""}}]
  end

  defp entity_to_tags(_, _offset, _length), do: []

  # --- Text utilities ---

  @doc """
  HTML-escape a string, replacing `&`, `<`, `>`, and `"` with entities.
  """
  @spec escape_html(String.t()) :: String.t()
  def escape_html(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  @doc """
  Convert macron markers (`e>` → `ē`, `o>` → `ō`) in HTML-escaped text.
  """
  @spec macronize(String.t()) :: String.t()
  def macronize(text) do
    text
    |> String.replace("e&gt;", "ē")
    |> String.replace("o&gt;", "ō")
  end

  @doc """
  Convert straight quotes and apostrophes to their curly/smart equivalents.
  """
  @spec smartquotes(String.t()) :: String.t()
  def smartquotes(text) do
    text
    # Apostrophes in contractions first (word'word)
    |> String.replace(~r/(\w)'(\w)/, "\\1\u2019\\2")
    # Double quotes via toggle (odd = open, even = close)
    |> replace_double_quotes()
    # Opening single quote after whitespace or start of string
    |> String.replace(~r/(^|\s)'/, "\\1\u2018")
    # Remaining single quotes → right single quote (closing/apostrophe)
    |> String.replace("'", "\u2019")
  end

  defp replace_double_quotes(text) do
    parts = String.split(text, "\"", parts: :infinity)

    {result, _} =
      Enum.reduce(parts, {"", true}, fn segment, {acc, is_open} ->
        if acc == "" do
          {segment, is_open}
        else
          quote_char = if is_open, do: "\u201C", else: "\u201D"
          {acc <> quote_char <> segment, !is_open}
        end
      end)

    result
  end

  # --- Asset copying ---

  @doc """
  Copy CSS assets from Kodon's priv directory to the output directory.
  """
  @spec copy_css(String.t()) :: :ok
  def copy_css(output_dir) do
    File.mkdir_p!(Path.join(output_dir, "css"))

    css_src =
      Path.join(
        Application.app_dir(:kodon, Path.join(["priv", "assets", "css"])),
        "style.css"
      )

    if File.exists?(css_src) do
      File.cp!(css_src, Path.join(output_dir, "css/style.css"))
    end

    :ok
  end
end
