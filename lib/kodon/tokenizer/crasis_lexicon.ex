defmodule Kodon.Tokenizer.CrasisLexicon do
  @moduledoc """
  Lexicon of known Ancient Greek crasis forms.

  Crasis merges two words into one, marking the junction with a coronis
  (U+02BC) that is visually identical to a smooth breathing.  Because the
  coronis cannot be distinguished from a breathing by surface inspection alone,
  classification must rely on a known-form list.

  ## Lookup strategy

  `crasis?/1` normalizes its input before lookup:

    1. Lowercase via `String.downcase/1`.
    2. Strip all combining diacritics (accents, breathings, iota subscript)
       so the lexicon keys are plain base letters plus the coronis.

  This keeps the lexicon compact: one entry covers all accentual variants of
  the same crasis form (e.g. `κἀγώ` and `κἀγω` both match `κἀγω`).

  ## Extending the lexicon

  Add entries to `@crasis_forms` as bare downcased base-letter strings with
  the coronis (U+02BC) at the contraction point.  Do not include accents or
  breathings — the normalization step removes them before comparison.

  Primary sources for crasis forms:
    - Smyth, *Greek Grammar* §§ 62–68
    - Kühner–Blass, *Ausführliche Grammatik* I §iii
    - Attestations in LSJ headwords
  """

  # U+02BC MODIFIER LETTER APOSTROPHE — the canonical coronis / apostrophe
  # used throughout the tokenizer.
  @coronis "\u02BC"

  # ---------------------------------------------------------------------------
  # Known crasis forms (downcased, diacritics stripped, coronis retained).
  #
  # Format: the merged word with U+02BC marking the crasis point.
  # Common contractions of καί, τό/τά/τοί/ταί, ὁ/ἡ, ἐγώ, εἰ, and ἐκεῖ.
  # ---------------------------------------------------------------------------

  @crasis_forms MapSet.new([
                  # καί + ἐγώ / ἐμοί / ἐμέ
                  "κ#{@coronis}αγω",
                  "κ#{@coronis}αγωγε",
                  "κ#{@coronis}αμοι",
                  "κ#{@coronis}αμε",
                  # καί + article forms
                  # καί + ὁ ἕτερος (contracted chain)
                  "κ#{@coronis}αθατερος",
                  # καί + ἄλλα
                  "κ#{@coronis}αλλα",
                  # καί + ἔπειτα
                  "κ#{@coronis}απειτα",
                  # καί + εἶτα
                  "κ#{@coronis}ατα",
                  # τό / τά + ἄλλα / ἄλλο / ἐναντία etc.
                  # τά + ἄλλα
                  "τ#{@coronis}αλλα",
                  # τό + ἄλλο
                  "τ#{@coronis}αλλο",
                  # τά + ἐναντία
                  "τ#{@coronis}αναντια",
                  # τῷ + ἀνδρί
                  "τ#{@coronis}ανδρι",
                  # τοῦ + ἀνδρός
                  "τ#{@coronis}ανδρος",
                  # τῷ + ἀνθρώπῳ
                  "τ#{@coronis}ανθρωπω",
                  # τό + ἄρα
                  "τ#{@coronis}αρα",
                  # τό + αὐτό
                  "τ#{@coronis}αυτο",
                  # τόν + αὐτόν
                  "τ#{@coronis}αυτον",
                  # τῆς + αὐτῆς
                  "τ#{@coronis}αυτης",
                  # τοῖς + αὐτοῖς
                  "τ#{@coronis}αυτοις",
                  # τά + αὐτά
                  "τ#{@coronis}αυτα",
                  # ὁ / ἡ + ἕτερος family
                  # τό + ἕτερον
                  "θ#{@coronis}ατερον",
                  # ὁ + ἕτερος
                  "θ#{@coronis}ατερος",
                  # ἡ + ἑτέρα
                  "θ#{@coronis}ατερα",
                  # τοῖς + ἑτέροις
                  "θ#{@coronis}ατεροις",
                  # εἰ + ἄν
                  # εἰ + ἄν  (= ἐάν, written as crasis in some mss.)
                  "ε#{@coronis}αν",
                  # ἐκεῖ + σε
                  # ἐκεῖ + σε (rare)
                  "εκ#{@coronis}εισε",
                  # ὦ + ἄγαθε (exclamative crasis)
                  "ω#{@coronis}γαθε",
                  "ω#{@coronis}γαθον"
                ])

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Returns `true` if `word` is a known crasis form, `false` otherwise.

  `word` is normalized (lowercased, diacritics stripped) before lookup, so
  accentual variants match the same lexicon entry.

  ## Examples

      iex> Kodon.Tokenizer.CrasisLexicon.crasis?("κἀγώ")
      true

      iex> Kodon.Tokenizer.CrasisLexicon.crasis?("τἄλλα")
      true

      iex> Kodon.Tokenizer.CrasisLexicon.crasis?("εἶπεν")
      false
  """
  @spec crasis?(String.t()) :: boolean()
  def crasis?(word) when is_binary(word) do
    word
    |> normalize_for_lookup()
    |> then(&MapSet.member?(@crasis_forms, &1))
  end

  @doc """
  Returns the full set of known crasis forms (in lookup-normalized form).

  Intended for testing and inspection; prefer `crasis?/1` for classification.
  """
  @spec all() :: MapSet.t(String.t())
  def all, do: @crasis_forms

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  # Lowercase and strip all combining diacritics, but keep the coronis (U+02BC)
  # since it is a spacing modifier letter — not a combining character — and is
  # the structural marker we actually care about.
  #
  # Unicode combining characters used in polytonic Greek:
  #   \u0300–\u036F  Combining Diacritical Marks (accents, breathings)
  #   \u1DC0–\u1DFF  Combining Diacritical Marks Supplement
  #   \u0345         COMBINING GREEK YPOGEGRAMMENI (iota subscript)
  #
  # We decompose to NFD first so that precomposed letters (e.g. ά U+03AC)
  # split into base + combining accent, then strip the combiners, then
  # recompose to NFC.  The coronis survives because it is not a combining mark.

  @diacritic_pattern Regex.compile!(
                       # Combining Diacritical Marks (accents, breathings)
                       # Combining Diacritical Marks Supplement
                       # Combining Greek Ypogegrammeni (iota subscript)
                       "[" <>
                         "\u0300-\u036F" <>
                         "\u1DC0-\u1DFF" <>
                         "\u0345" <>
                         "]"
                     )
  defp normalize_for_lookup(word) do
    word
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(@diacritic_pattern, "")
    |> String.normalize(:nfc)
  end
end
