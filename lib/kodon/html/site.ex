defmodule Kodon.HTML.Site do
  use NimblePublisher,
    build: Kodon.HTML.Passage,
    from: Application.compile_env(:kodon, :tei_glob),
    as: :passages,
    parser: Kodon.HTML.Parser

  def all_passages, do: @passages
end
