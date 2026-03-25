defmodule Kodon.Tokenizer.Token do
  @moduledoc """
  The fundamental unit produced by `Kodon.Tokenizer.Scanner` and refined by
  `Kodon.Tokenizer.Classifier`.

  ## Fields

    - `:type`                 - coarse token category; one of `:word` or
                              `:punctuation`.  The scanner never produces
                              `:whitespace` tokens; spacing is recorded on the
                              token that *precedes* the space (see below).
    - `:text`                 - the raw grapheme string for this token, exactly
                              as it appears in the normalized source.
    - `:has_trailing_space?`  - `true` when a single space followed this token in
                              the source.  Sufficient for Ancient Greek prose,
                              where inter-token spacing is always a single space
                              after normalization.  Defaults to `false`.
    - `:metadata`             - open map for classifier and downstream annotations
                              (e.g. `%{elided: true}`, `%{crasis: true}`).
                              Defaults to `%{}`.

  ## Reconstructing the source

  Because `has_trailing_space?` captures spacing, the original normalized text
  can be reconstructed losslessly from a token list:

      tokens
      |> Enum.map_join(fn t ->
           if t.has_trailing_space?, do: t.text <> " ", else: t.text
         end)

  Note that the *last* token in a sentence will always have
  `has_trailing_space?: false` (normalization strips trailing whitespace), so
  no special-casing is needed at the boundary.
  """

  @type token_type :: :word | :punctuation

  @type t :: %__MODULE__{
          type: token_type(),
          text: String.t(),
          has_trailing_space?: boolean(),
          metadata: map()
        }

  defstruct [
    :type,
    :text,
    has_trailing_space?: false,
    metadata: %{}
  ]

  @doc """
  Creates a new token with `type` and `text`, and all other fields at their
  defaults.
  """
  @spec new(token_type(), String.t()) :: t()
  def new(type, text) do
    %__MODULE__{type: type, text: text}
  end

  @doc """
  Returns a copy of `token` with `has_trailing_space?` set to `true`.
  """
  @spec mark_trailing_space(t()) :: t()
  def mark_trailing_space(%__MODULE__{} = token) do
    %{token | has_trailing_space?: true}
  end

  @doc """
  Merges `attrs` into the token's `:metadata` map.

  Existing keys are overwritten by values in `attrs`.

  ## Example

      iex> token = Token.new(:word, "ἀπʼ")
      iex> Token.put_metadata(token, %{elided: true})
      %Token{type: :word, text: "ἀπʼ", metadata: %{elided: true}, ...}
  """
  @spec put_metadata(t(), map()) :: t()
  def put_metadata(%__MODULE__{} = token, attrs) when is_map(attrs) do
    %{token | metadata: Map.merge(token.metadata, attrs)}
  end
end
