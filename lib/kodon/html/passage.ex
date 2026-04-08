defmodule Kodon.HTML.Passage do
  defstruct [:body, :table_of_contents, :title, :type, :urn]

  @type t :: %__MODULE__{
          body: map(),
          table_of_contents: [map()],
          title: String.t(),
          type: :cts_metadata | :tei_xml,
          urn: String.t(),
        }

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
