defmodule Kodon.HTML.Passage do
  defstruct [:body, :table_of_contents, :urn, :title, :type]

  def build(_filename, %{type: :cts_metadata}, body) do
    struct!(__MODULE__,
      urn: "urn",
      title: "title",
      table_of_contents: [],
      type: :cts_metadata,
      body: body
    )
  end

  def build(
        _filename,
        %{type: :tei_xml, urn: urn, title: title, table_of_contents: toc},
        body
      ) do
    struct!(__MODULE__,
      urn: urn,
      title: title,
      table_of_contents: toc,
      type: :tei_xml,
      body: body
    )
  end
end
