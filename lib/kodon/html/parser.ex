defmodule Kodon.HTML.Parser do
  def parse(path, contents) do
    if String.ends_with?(path, "__cts__.xml") do
      {%{type: :cts_metadata}, contents}
    else
      parsed = Kodon.TEIParser.parse_string(contents)
      table_of_contents = Kodon.TEIParser.create_table_of_contents(parsed.textparts)

      case table_of_contents do
        [] ->
          {%{type: :tei_xml, table_of_contents: [], title: parsed.urn, urn: parsed.urn},
           parsed.elements}

        _ ->
          table_of_contents
          |> Enum.reduce([], fn tp, acc ->
            [
              {%{
                 type: :tei_xml,
                 table_of_contents: table_of_contents,
                 title: parsed.urn,
                 urn: parsed.urn
               }, elements_for_textpart(parsed.elements, tp)}
              | acc
            ]
          end)
          |> Enum.reverse()
      end
    end
  end

  defp elements_for_textpart(elements, textpart) do
    elements |> Enum.filter(fn e -> e.textpart_index == textpart.index end)
  end
end
