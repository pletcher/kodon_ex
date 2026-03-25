defmodule Kodon.Tokenizer.Scanner do
  @moduledoc """
  Grapheme-level scanner that converts a normalized Ancient Greek string into
  a flat list of raw `%Token{}` structs.

  At this stage every token has type `:word` or `:punctuation`.  Finer
  classification (elision, crasis) is left to `Kodon.Tokenizer.Classifier`.

  Expects input to have already been processed by `Kodon.Tokenizer.Normalizer`,
  i.e.:
    - NFC-normalized
    - All apostrophe variants unified to U+02BC
    - Exotic whitespace collapsed to ASCII space

  ## Token types produced

    - `:word`        — a run of Greek (or mixed) non-whitespace, non-punctuation
                       graphemes, possibly ending with the canonical apostrophe
                       (elided) or containing an internal U+02BC (crasis candidate)
    - `:punctuation` — a single punctuation grapheme (see @punctuation below)

  Whitespace is not emitted as a token type.  Instead, when a space follows a
  token, that token's `has_trailing_space?` field is set to `true`.  This keeps
  the list compact while remaining lossless for single-space inter-token gaps,
  which is all that normalized Ancient Greek prose requires.

  ## Design notes

  The scanner works by walking the grapheme cluster list produced by
  `String.graphemes/1` one element at a time, accumulating word characters
  into a buffer and flushing that buffer whenever a non-word character is
  encountered.  This is O(n) and avoids regex backtracking on Unicode text.
  """

  alias Kodon.Tokenizer.Token

  # ---------------------------------------------------------------------------
  # Punctuation set
  #
  # Greek-specific:
  #   U+00B7  MIDDLE DOT / ANO TELEIA  ·   (clause separator)
  #   U+003B  SEMICOLON               ;    (Greek question mark in modern ed.)
  #   U+037E  GREEK QUESTION MARK     ;    (canonical Greek question mark)
  #   U+0387  GREEK ANO TELEIA        ·    (canonical Greek middle dot)
  #
  # Standard Latin punctuation that appears in modern critical editions:
  #   . , : ! ? ( ) [ ] { } — – - " "
  # ---------------------------------------------------------------------------

  @punctuation MapSet.new([
                 # Greek-specific
                 # MIDDLE DOT (ano teleia variant)
                 "\u00B7",
                 # GREEK ANO TELEIA
                 "\u0387",
                 # SEMICOLON (used as Greek question mark in many editions)
                 "\u003B",
                 # GREEK QUESTION MARK
                 "\u037E",
                 # Standard
                 ".",
                 ",",
                 ":",
                 "!",
                 "?",
                 "(",
                 ")",
                 "[",
                 "]",
                 "{",
                 "}",
                 # EM DASH
                 "\u2014",
                 # EN DASH
                 "\u2013",
                 "-",
                 # LEFT / RIGHT DOUBLE QUOTATION MARK
                 "\u201C",
                 "\u201D",
                 # LEFT / RIGHT SINGLE QUOTATION MARK
                 "\u2018",
                 "\u2019"
                 # (right single = apostrophe variant; Normalizer
                 #  converts it to U+02BC before we get here, so this
                 #  entry is a safety net for any that slipped through)
               ])

  @space " "
  @canonical_apostrophe Kodon.Tokenizer.Normalizer.canonical_apostrophe()

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Scans `text` (assumed already normalized) into a list of `%Token{}` structs
  in document order.

  Whitespace is not emitted as a token.  Instead, a space following a token
  sets `has_trailing_space?: true` on that token.

  ## Examples

      iex> Kodon.Tokenizer.Scanner.scan("ἀπʼ ἐμοῦ.")
      [
        %Token{type: :word,        text: "ἀπʼ",    has_trailing_space?: true},
        %Token{type: :word,        text: "ἐμοῦ",   has_trailing_space?: false},
        %Token{type: :punctuation, text: ".",       has_trailing_space?: false},
      ]

      iex> Kodon.Tokenizer.Scanner.scan("εἶπεν· καὶ ἐγένετο")
      [
        %Token{type: :word,        text: "εἶπεν",   has_trailing_space?: false},
        %Token{type: :punctuation, text: "·",        has_trailing_space?: true},
        %Token{type: :word,        text: "καὶ",     has_trailing_space?: true},
        %Token{type: :word,        text: "ἐγένετο", has_trailing_space?: false},
      ]
  """
  @spec scan(String.t()) :: [Token.t()]
  def scan(text) when is_binary(text) do
    text
    |> String.graphemes()
    |> do_scan([], [])
    |> Enum.reverse()
  end

  # ---------------------------------------------------------------------------
  # Private — recursive grapheme walker
  #
  # State:
  #   graphemes  — remaining grapheme clusters to process
  #   buf        — reversed list of graphemes accumulated for the current word
  #   tokens     — reversed list of completed tokens
  # ---------------------------------------------------------------------------

  # Base case: no more graphemes.  Flush any remaining word buffer.
  defp do_scan([], buf, tokens) do
    flush_word(buf, tokens)
  end

  # Whitespace: flush any word in progress and mark the head token as having a
  # trailing space.  If the buffer was empty (e.g. space immediately after
  # punctuation), the most-recently emitted token gets the mark instead.
  # A leading space with no preceding token at all is silently dropped —
  # Normalizer.normalize/1 guarantees this won't occur in normal usage.
  defp do_scan([@space | rest], buf, tokens) do
    tokens =
      case flush_word(buf, tokens) do
        [] -> []
        [head | tail] -> [Token.mark_trailing_space(head) | tail]
      end

    do_scan(rest, [], tokens)
  end

  # Punctuation: flush any word in progress, emit a punctuation token.
  # Special case: U+02BC at a non-word-internal position is itself punctuation
  # (shouldn't normally happen after normalization, but be defensive).
  defp do_scan([g | rest], buf, tokens)
       when is_map_key(@punctuation, g) or
              (g == @canonical_apostrophe and buf == []) do
    tokens =
      buf
      |> flush_word(tokens)
      |> prepend_token(:punctuation, g)

    do_scan(rest, [], tokens)
  end

  # Canonical apostrophe mid-word or at word end: accumulate into the buffer.
  # The classifier will later decide whether this is elision or crasis.
  defp do_scan([@canonical_apostrophe | rest], buf, tokens) do
    do_scan(rest, [@canonical_apostrophe | buf], tokens)
  end

  # Ordinary word grapheme: accumulate.
  defp do_scan([g | rest], buf, tokens) do
    do_scan(rest, [g | buf], tokens)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Turns the reversed grapheme buffer into a :word token and prepends it to
  # the token list.  If the buffer is empty, returns the token list unchanged.
  defp flush_word([], tokens), do: tokens

  defp flush_word(buf, tokens) do
    text = buf |> Enum.reverse() |> Enum.join()
    prepend_token(tokens, :word, text)
  end

  defp prepend_token(tokens, type, text) do
    [Token.new(type, text) | tokens]
  end
end
