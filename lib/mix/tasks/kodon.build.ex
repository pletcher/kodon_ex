defmodule Mix.Tasks.Kodon.Build do
  use Mix.Task

  @shortdoc "Build a Kodon site"

  @moduledoc """
  Builds a Kodon site by rendering all compiled passages to static HTML files.

  ## Usage

      mix kodon.build

  Passages are written to `<output_dir>/passages/<urn>.html`, where `:output_dir`
  defaults to `"output"`. CSS assets are copied to `<output_dir>/css/`.

  Passages of type `:cts_metadata` (`__cts__.xml` files) are skipped.
  """

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    output_dir = Application.get_env(:kodon, :output_dir, "output")
    passages_dir = Path.join(output_dir, "passages")

    File.mkdir_p!(passages_dir)
    Kodon.Renderer.copy_css(output_dir)

    passages = Kodon.HTML.Site.all_passages() |> Enum.filter(&(&1.type == :tei_xml))

    Mix.shell().info("Building #{length(passages)} passage(s)...")

    Enum.each(passages, fn passage ->
      html = Kodon.Renderer.render_section(passage, [])
      path = Path.join(passages_dir, passage.urn <> ".html")
      File.write!(path, html)
      Mix.shell().info("  wrote #{path}")
    end)

    Mix.shell().info("Done.")
  end
end
