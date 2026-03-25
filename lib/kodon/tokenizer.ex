defmodule Kodon.Tokenizer do
  @moduledoc """
  Public API for the Ancient Greek tokenizer.

  Wires the internal pipeline together:

      raw string
        → `Kodon.Tokenizer.Normalizer.normalize/1`   (NFC, apostrophe unification, whitespace)
        → `Kodon.Tokenizer.Scanner.scan/1`            (grapheme walk → raw tokens)
        → `Kodon.Tokenizer.Classifier.classify/1`     (elision, crasis annotation)

  ## Quick start

      iex> Kodon.Tokenizer.tokenize("κἀγὼ εἶπον δʼ ὅτι καλόν.")
      [
        %Kodon.Tokenizer.Token{type: :word, text: "κἀγὼ",  metadata: %{crasis: true},  has_trailing_space?: true},
        %Kodon.Tokenizer.Token{type: :word, text: "εἶπον", metadata: %{},               has_trailing_space?: true},
        %Kodon.Tokenizer.Token{type: :word, text: "δʼ",    metadata: %{elided: true},   has_trailing_space?: true},
        %Kodon.Tokenizer.Token{type: :word, text: "ὅτι",   metadata: %{},               has_trailing_space?: true},
        %Kodon.Tokenizer.Token{type: :word, text: "καλόν", metadata: %{},               has_trailing_space?: false},
        %Kodon.Tokenizer.Token{type: :punctuation, text: ".", metadata: %{},            has_trailing_space?: false},
      ]

  ## Pipeline access

  Each stage is also callable directly if you need intermediate results or
  want to substitute your own implementation:

      text
      |> Kodon.Tokenizer.normalize()
      |> Kodon.Tokenizer.scan()
      |> Kodon.Tokenizer.classify()

  ## Reconstruction

  The original normalized text can be recovered losslessly from any token list:

      Kodon.Tokenizer.reconstruct(tokens)
  """

  alias Kodon.Tokenizer.{Classifier, Normalizer, Scanner, Token}

  # ---------------------------------------------------------------------------
  # Main entry point
  # ---------------------------------------------------------------------------

  @doc """
  Tokenizes `text`, running the full normalize → scan → classify pipeline.

  Returns a list of `%Token{}` structs in document order.  Raises
  `ArgumentError` if `text` is not a binary.

  ## Options

  None currently.  Options for future extension (e.g. `:keep_whitespace`,
  `:strip_diacritics`) should be added here as a keyword list.

  ## Examples

      iex> Kodon.Tokenizer.tokenize("ἀπ' ἐμοῦ.")
      [
        %Token{type: :word,        text: "ἀπʼ",   metadata: %{elided: true}, has_trailing_space?: true},
        %Token{type: :word,        text: "ἐμοῦ",  metadata: %{},             has_trailing_space?: false},
        %Token{type: :punctuation, text: ".",      metadata: %{},             has_trailing_space?: false},
      ]

      iex> Kodon.Tokenizer.tokenize("")
      []
  """
  @spec tokenize(String.t()) :: [Token.t()]
  def tokenize(text) when is_binary(text) do
    text
    |> normalize()
    |> scan()
    |> classify()
  end

  # ---------------------------------------------------------------------------
  # Pipeline stages (thin delegating wrappers)
  #
  # Exposed so callers can run partial pipelines, swap stages during testing,
  # or inspect intermediate results without depending on internal module names.
  # ---------------------------------------------------------------------------

  @doc """
  Runs `Kodon.Tokenizer.Normalizer.normalize/1` on `text`.

  Applies NFC normalization, apostrophe unification, and whitespace
  collapsing.  This is always the first stage of the pipeline.
  """
  @spec normalize(String.t()) :: String.t()
  defdelegate normalize(text), to: Normalizer

  @doc """
  Runs `Kodon.Tokenizer.Scanner.scan/1` on a normalized string.

  Expects input already processed by `normalize/1`.  Returns a flat list of
  raw `:word` and `:punctuation` tokens with `has_trailing_space?` set but no
  metadata annotations yet.
  """
  @spec scan(String.t()) :: [Token.t()]
  defdelegate scan(text), to: Scanner

  @doc """
  Runs `Kodon.Tokenizer.Classifier.classify/1` on a scanned token list.

  Expects input already produced by `scan/1`.  Annotates `:word` tokens with
  elision and crasis metadata; passes `:punctuation` tokens through unchanged.
  """
  @spec classify([Token.t()]) :: [Token.t()]
  defdelegate classify(tokens), to: Classifier

  # ---------------------------------------------------------------------------
  # Utilities
  # ---------------------------------------------------------------------------

  @doc """
  Reconstructs the normalized source text from a token list.
  ?
  Lossless for any list produced by this pipeline, since `has_trailing_space?`
  captures all inter-token spacing.  Useful for round-trip testing and for
  serializing a modified token list back to text.

  ## Example

      iex> tokens = Kodon.Tokenizer.tokenize("ἀπʼ ἐμοῦ.")
      iex> Kodon.Tokenizer.reconstruct(tokens)
      "ἀπʼ ἐμοῦ."
  """
  @spec reconstruct([Token.t()]) :: String.t()
  def reconstruct(tokens) when is_list(tokens) do
    Enum.map_join(tokens, fn token ->
      if token.has_trailing_space?, do: token.text <> " ", else: token.text
    end)
  end

  @doc """
  Returns only the `:word` tokens from `tokens`, discarding punctuation.

  Useful when punctuation is not relevant to downstream processing (e.g.
  feeding a morphological analyser).
  """
  @spec words([Token.t()]) :: [Token.t()]
  def words(tokens) when is_list(tokens) do
    Enum.filter(tokens, &(&1.type == :word))
  end

  @doc """
  Returns only the `:punctuation` tokens from `tokens`.
  """
  @spec punctuation([Token.t()]) :: [Token.t()]
  def punctuation(tokens) when is_list(tokens) do
    Enum.filter(tokens, &(&1.type == :punctuation))
  end

  @doc """
  Returns all tokens whose metadata includes the given key set to `true`.

  ## Example

      iex> tokens = Kodon.Tokenizer.tokenize("κἀγὼ δʼ εἶπον")
      iex> Kodon.Tokenizer.with_metadata(tokens, :elided)
      [%Token{text: "δʼ", metadata: %{elided: true}, ...}]

      iex> Kodon.Tokenizer.with_metadata(tokens, :crasis)
      [%Token{text: "κἀγὼ", metadata: %{crasis: true}, ...}]
  """
  @spec with_metadata([Token.t()], atom()) :: [Token.t()]
  def with_metadata(tokens, key) when is_list(tokens) and is_atom(key) do
    Enum.filter(tokens, &Map.get(&1.metadata, key, false))
  end
end
