defmodule Kodon.HTML.Site do
  use NimblePublisher,
    build: Kodon.HTML.Page,
    from: Application.compile_env(:kodon, :tei_glob),
    as: :pages,
    parser: Kodon.HTML.Parser

  def all_pages, do: @pages
end
