defmodule Kodon.Tokenizer.Classifier do
  @moduledoc """
  Refines the coarse token list produced by `Kodon.Tokenizer.Scanner` by
  annotating `:word` tokens with linguistic metadata.

  Punctuation tokens pass through unchanged.  For each `:word` token the
  classifier applies three independent checks in order:

    1. **Elision** — the token ends with the canonical apostrophe (U+02BC).
       These are unambiguous: `ἀπʼ`, `δʼ`, `τʼ`, etc.

    2. **Crasis** — the token appears in the known crasis lexicon.
       Crasis words carry an internal coronis that is visually identical to a
       smooth breathing, so lexicon lookup is the only reliable detection
       strategy at this level (see `Kodon.Tokenizer.CrasisLexicon`).

    3. **Proclitics / enclitics** (future; slot reserved in metadata).

  Results are written into `token.metadata` using `Token.put_metadata/2`:

    - `%{elided: true}`  for elided tokens
    - `%{crasis: true}`  for crasis tokens
    - `%{}`              for ordinary words (metadata left empty)

  A token may, in principle, be both elided and crasis, though this is
  vanishingly rare; both flags are set independently.

  ## What this module does NOT do

    - It does not strip the apostrophe from elided tokens — that is a
      normalization choice for a later, optional step.
    - It does not attempt morphological analysis or lemmatization.
    - It does not modify punctuation tokens.
  """

  alias Kodon.Tokenizer.Token
  alias Kodon.Tokenizer.CrasisLexicon

  @canonical_apostrophe Kodon.Tokenizer.Normalizer.canonical_apostrophe()

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Classifies every token in `tokens`, returning a new list with metadata
  annotations added to `:word` tokens.

  The input list is typically the output of `Kodon.Tokenizer.Scanner.scan/1`.
  Punctuation tokens are passed through without modification.

  ## Example

      iex> tokens = Kodon.Tokenizer.Scanner.scan("κἀγὼ εἶπον δʼ ὅτι")
      iex> Kodon.Tokenizer.Classifier.classify(tokens)
      [
        %Token{type: :word, text: "κἀγὼ",  metadata: %{crasis: true},  ...},
        %Token{type: :word, text: "εἶπον", metadata: %{},               ...},
        %Token{type: :word, text: "δʼ",    metadata: %{elided: true},   ...},
        %Token{type: :word, text: "ὅτι",   metadata: %{},               ...},
      ]
  """
  @spec classify([Token.t()]) :: [Token.t()]
  def classify(tokens) when is_list(tokens) do
    Enum.map(tokens, &classify_token/1)
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  # Punctuation tokens are passed through unchanged.
  defp classify_token(%Token{type: :punctuation} = token), do: token

  # Word tokens get elision and crasis checks.
  defp classify_token(%Token{type: :word} = token) do
    token
    |> maybe_mark_elision()
    |> maybe_mark_crasis()
  end

  # ---------------------------------------------------------------------------
  # Elision
  #
  # A word is elided when its final grapheme cluster is the canonical
  # apostrophe.  We check the last grapheme rather than using
  # String.ends_with?/2 so that the check is grapheme-aware (safe for all
  # NFC-normalized Greek text, but good practice regardless).
  # ---------------------------------------------------------------------------

  defp maybe_mark_elision(%Token{text: text} = token) do
    if elided?(text) do
      Token.put_metadata(token, %{elided: true})
    else
      token
    end
  end

  defp elided?(text) do
    text
    |> String.graphemes()
    |> List.last() ==
      @canonical_apostrophe
  end

  # ---------------------------------------------------------------------------
  # Crasis
  #
  # Crasis cannot be detected from surface form alone because the coronis is
  # visually and codepoint-identical to a smooth breathing mark.  We therefore
  # look up every word token in the crasis lexicon.
  #
  # Lookup is performed on the lowercased, unaccented form so that the lexicon
  # does not need to enumerate all accentual variants.  Stripping accents here
  # is a local concern of the classifier and does not mutate the token text.
  # ---------------------------------------------------------------------------

  defp maybe_mark_crasis(%Token{text: text} = token) do
    if CrasisLexicon.crasis?(text) do
      Token.put_metadata(token, %{crasis: true})
    else
      token
    end
  end
end
