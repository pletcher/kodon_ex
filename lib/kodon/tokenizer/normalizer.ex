defmodule Kodon.Tokenizer.Normalizer do
  @moduledoc """
  Unicode normalization and surface-form cleanup for Ancient Greek text.

  Responsibilities:
    1. NFC normalization — ensures all precomposed and decomposed diacritic
       forms are unified before any grapheme-level work.
    2. Apostrophe unification — maps the several codepoints used to mark
       elision (curly apostrophe, modifier letter apostrophe, Greek koronis,
       Greek psili) to a single canonical apostrophe (U+02BC MODIFIER LETTER
       APOSTROPHE) so downstream code has one form to check.
    3. Whitespace normalization — collapses runs of whitespace (including
       non-breaking spaces, which appear in some digital Greek texts) to a
       single ASCII space, and strips leading/trailing whitespace.

  What this module does NOT do:
    - Strip diacritics (that is an optional later step, not normalization).
    - Detect elision or crasis (that belongs in the classifier).
    - Tokenize (that belongs in the scanner).
  """

  # ---------------------------------------------------------------------------
  # Apostrophe / coronis unification
  #
  # All of these are used in Greek digital texts to represent elision or
  # act as a coronis in crasis.  We normalise them all to U+02BC so that a
  # single pattern check is sufficient everywhere else.
  #
  #   U+0027  APOSTROPHE                  '
  #   U+2019  RIGHT SINGLE QUOTATION MARK '
  #   U+02BC  MODIFIER LETTER APOSTROPHE  ʼ   ← our canonical form
  #   U+02BD  MODIFIER LETTER REVERSED COMMA ʽ (rough-breathing lookalike)
  #   U+0313  COMBINING COMMA ABOVE           (smooth breathing / koronis in
  #   U+1FBD  GREEK KORONIS               ᾽    decomposed or standalone form)
  #   U+1FBF  GREEK PSILI                 ᾿
  # ---------------------------------------------------------------------------

  @apostrophe_variants [
    # APOSTROPHE
    "\u0027",
    # RIGHT SINGLE QUOTATION MARK
    "\u2019",
    # MODIFIER LETTER REVERSED COMMA
    "\u02BD",
    # COMBINING COMMA ABOVE (standalone / after NFC oddities)
    "\u0313",
    # GREEK KORONIS
    "\u1FBD",
    # GREEK PSILI
    "\u1FBF"
  ]

  @canonical_apostrophe "\u02BC"

  # Whitespace codepoints beyond ASCII space that appear in digital corpora.
  @extra_whitespace [
    # NO-BREAK SPACE
    "\u00A0",
    # THIN SPACE
    "\u2009",
    # HAIR SPACE
    "\u200A",
    # NARROW NO-BREAK SPACE
    "\u202F",
    # IDEOGRAPHIC SPACE (occasionally in mixed-encoding files)
    "\u3000"
  ]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Runs the full normalisation pipeline on `text` and returns the cleaned
  string.  Steps are applied in order:

    1. NFC
    2. apostrophe unification
    3. whitespace normalisation

  ## Examples

      iex> Kodon.Tokenizer.Normalizer.normalize("ἀπ' ἐμοῦ")
      "ἀπʼ ἐμοῦ"

      iex> Kodon.Tokenizer.Normalizer.normalize("  καὶ\\u00A0εἶπεν  ")
      "καὶ εἶπεν"
  """
  @spec normalize(String.t()) :: String.t()
  def normalize(text) when is_binary(text) do
    text
    |> nfc()
    |> unify_apostrophes()
    |> normalize_whitespace()
  end

  @doc """
  Applies Unicode NFC normalization.

  Precomposed characters (e.g. ά as a single codepoint) and their
  canonically equivalent decomposed sequences (base letter + combining
  accent) are unified to NFC precomposed form.
  """
  @spec nfc(String.t()) :: String.t()
  def nfc(text), do: String.normalize(text, :nfc)

  @doc """
  Replaces all apostrophe-like codepoints with the canonical
  U+02BC MODIFIER LETTER APOSTROPHE.

  Call `nfc/1` before this function so that any combining characters that
  would otherwise interfere are already in their composed forms.
  """
  @spec unify_apostrophes(String.t()) :: String.t()
  def unify_apostrophes(text) do
    Enum.reduce(@apostrophe_variants, text, fn variant, acc ->
      String.replace(acc, variant, @canonical_apostrophe)
    end)
  end

  @doc """
  Collapses all runs of whitespace (including non-breaking and other Unicode
  space characters) to a single ASCII space, then strips leading and trailing
  whitespace.
  """
  @spec normalize_whitespace(String.t()) :: String.t()
  def normalize_whitespace(text) do
    # Replace exotic spaces with a plain space first.
    collapsed =
      Enum.reduce(@extra_whitespace, text, fn ws, acc ->
        String.replace(acc, ws, " ")
      end)

    # Collapse runs of spaces / tabs / newlines to one space.
    collapsed
    |> String.replace(~r/[ \t\r\n]+/, " ")
    |> String.trim()
  end

  @doc """
  Returns the canonical apostrophe codepoint used throughout the tokenizer.

  Useful in other modules that need to match against it without hard-coding
  the literal character.
  """
  @spec canonical_apostrophe() :: String.t()
  def canonical_apostrophe, do: @canonical_apostrophe
end
