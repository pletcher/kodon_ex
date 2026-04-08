defmodule Kodon.HTML.Site do
  def all_passages do
    Application.get_env(:kodon, :tei_glob, "priv/data/**/*.xml")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.flat_map(fn path ->
      Kodon.HTML.Parser.parse(path, File.read!(path))
      |> List.wrap()
      |> Enum.map(fn {attrs, body} ->
        Kodon.HTML.Passage.build(path, attrs, body)
      end)
    end)
  end
end
