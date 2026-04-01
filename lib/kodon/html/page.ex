defmodule Kodon.HTML.Page do
  defstruct [:body, :table_of_contents, :urn, :title]

  def build(_filename, %{type: :cts_metadata}, body) do
    body
  end

  def build(
        _filename,
        %{type: :tei_xml, urn: urn, title: title, table_of_contents: toc},
        body
      ) do
    struct!(__MODULE__, urn: urn, title: title, table_of_contents: toc, body: body)
  end
end
