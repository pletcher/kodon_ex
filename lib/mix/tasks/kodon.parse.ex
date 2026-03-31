defmodule Mix.Tasks.Kodon.Parse do
  use Mix.Task

  @shortdoc "Parses TEI XML files into JSON."

  @moduledoc """
  Parses TEI XML files from a directory into JSON.

  ## Usage

      mix kodon.parse <input_dir> [--output <output_dir>]

  Finds all `.xml` files in `input_dir` (excluding `__cts__.xml`), parses each
  with `Kodon.TEIParser`, and writes the resulting JSON to `output_dir`.

  `output_dir` defaults to `cts_json` as a sibling of `input_dir`.
  """

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional, _} = OptionParser.parse(args, strict: [output: :string])

    input_dir =
      case positional do
        [dir | _] -> dir
        [] -> Mix.raise("Usage: mix kodon.parse <input_dir> [--output <output_dir>]")
      end

    output_dir =
      Keyword.get(opts, :output, Path.join(Path.dirname(input_dir), "cts_json"))

    xml_files =
      Path.join(input_dir, "**/*.xml")
      |> Path.wildcard()
      |> Enum.reject(&(Path.basename(&1) == "__cts__.xml"))

    if xml_files == [] do
      Mix.shell().info("No XML files found in #{input_dir}")
    else
      File.mkdir_p!(output_dir)

      Enum.each(xml_files, fn xml_path ->
        parse_and_write(xml_path, input_dir, output_dir)
      end)

      total = length(xml_files)
      Mix.shell().info("")
      Mix.shell().info("Wrote #{total} file#{if total == 1, do: "", else: "s"} to #{output_dir}.")
    end
  end

  defp parse_and_write(xml_path, input_dir, output_dir) do
    relative = Path.relative_to(xml_path, input_dir)
    json_path = Path.join(output_dir, Path.rootname(relative) <> ".json")

    json_path |> Path.dirname() |> File.mkdir_p!()

    Mix.shell().info("Parsing #{xml_path}...")

    parsed = Kodon.TEIParser.parse(xml_path)
    File.write!(json_path, Jason.encode!(parsed))
  end
end
