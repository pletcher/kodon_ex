defmodule Mix.Tasks.Kodon.Build do
  use Mix.Task

  @shortdoc "Build a Kodon site"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    # data_dir = Application.get_env(:kodon, :data_dir, "cts_json")
  end

  # defp render_site do
  # end
end
