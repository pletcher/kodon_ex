# Kodon

Kodon is a static site generator for scholarly editions of ancient texts. It powers the [AHCIP (A Homer Commentary in Progress)](https://github.com/open-commentaries/ahcip) project.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `kodon` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:kodon, "~> 0.1.0"}
  ]
end
```

## Configuration

Kodon accepts the following configuration keys:

```elixir
config :kodon,
  output_dir: "output",           # Where generated HTML goes
  commentary_dir: "commentary",   # Directory with commentary markdown files
  site_title: "Kodon",            # The title of your site, e.g., "A Homer Commentary in Progress"
  templates_dir: "path/to/custom" # Override default templates (optional)
```

### Template Overrides

Kodon ships with default templates in `priv/templates/`. To customize the look
of your site, set `:templates_dir` in your config to point to a directory
containing your own EEx templates. Any templates found there will be used
instead of the defaults.

## Usage

```bash
# Build the static site
mix kodon.build

# Start a development server
mix kodon.server
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/kodon>.
