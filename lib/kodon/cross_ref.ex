defmodule Kodon.CrossRef do
  @moduledoc """
  Handles cross-reference parsing and HTML link generation.

  Cross-refs use a configurable prefix (default `"I"`) in the format
  `PREFIX-BOOK.LINE` (e.g., `"I-1.372"`). These are rendered as links to
  `/passages/<slug>/<book>.html#line-<book>-<line>`.

  ## Configuration

  - `:cross_ref_prefix` — the prefix used in cross-ref strings (default: `"I"`)
  - `:cross_ref_default_slug` — the default work slug for generated links
    (default: `"tlg0012.tlg001"`)
  """

  @doc """
  Parse a cross-reference string like "I-1.372" into {book, line}.
  Returns nil if the string doesn't match the expected format.

  Uses the `:cross_ref_prefix` app env (default `"I"`) to match.
  """
  @spec parse(String.t()) :: {integer(), String.t()} | nil
  def parse(ref_string) do
    prefix = Application.get_env(:kodon, :cross_ref_prefix, "I")

    case Regex.run(~r/#{Regex.escape(prefix)}-(\d+)\.(\d+[a-z]?)/, ref_string) do
      [_, book, line] -> {String.to_integer(book), line}
      _ -> nil
    end
  end

  @doc """
  Generate an HTML href for a cross-reference.

  Uses the `:cross_ref_default_slug` app env (default `"tlg0012.tlg001"`)
  as the work slug.
  """
  @spec to_href({integer(), String.t()}) :: String.t()
  def to_href({book, line}) do
    default_slug = Application.get_env(:kodon, :cross_ref_default_slug, "tlg0012.tlg001")
    to_href(default_slug, book, line)
  end

  @spec to_href(String.t()) :: String.t()
  def to_href(ref_string) when is_binary(ref_string) do
    case parse(ref_string) do
      nil -> "#"
      parsed -> to_href(parsed)
    end
  end

  @doc """
  Generate an HTML href with explicit work context.
  """
  @spec to_href(String.t(), integer(), String.t()) :: String.t()
  def to_href(work_slug, book, line) do
    "/passages/#{work_slug}/#{book}.html#line-#{book}-#{line}"
  end

  @doc """
  Generate an HTML anchor id for a line.
  """
  @spec line_id(term(), term()) :: String.t()
  def line_id(book_number, line_number) do
    "line-#{book_number}-#{line_number}"
  end

  @doc """
  Render a cross-reference "book.line" string as an HTML link.
  """
  @spec render_link(String.t()) :: String.t()
  def render_link(ref_string) do
    case Regex.run(~r/^(\d+)\.(\d+[a-z]?)$/, ref_string) do
      [_, book, line] ->
        href = to_href({String.to_integer(book), line})
        ~s(<a href="#{href}" class="cross-ref">#{book}.#{line}</a>)

      _ ->
        ref_string
    end
  end
end
