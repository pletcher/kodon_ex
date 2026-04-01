defmodule Kodon.TEIParser do
  @moduledoc """
  SAX-based TEI XML parser for TEI-encoded texts.

  Parses TEI XML files into a structured representation of textparts (structural
  divisions like books and cards) and elements (inline markup like paragraphs,
  notes, and milestones), correctly distinguishing inline annotations from base text.

  ## Architecture

  Unlike a DOM parser that loads the entire document tree into memory, this module
  uses SAX (Simple API for XML) parsing via Erlang's built-in `:xmerl_sax_parser`.
  Events are processed in a single pass, building up a tree of textparts and elements
  with proper parent-child relationships.

  ## Key concepts

  - **Textparts** — Structural divisions marked by `<div type="textpart">` elements.
    These form a hierarchy (e.g., book → card) and are identified by CTS URNs.
  - **Elements** — Inline markup (`<p>`, `<note>`, `<milestone>`, `<l>`, etc.) with
    children that can be text runs or nested elements.
  - **Text runs** — Sequences of character data within elements.
  - **Base text** — Text content excluding notes and editorial markup, extracted via
    `base_text/1`.

  Uses Erlang's built-in `:xmerl_sax_parser` (no external dependencies).
  """

  require Logger

  alias Kodon.Tokenizer

  defmodule Textpart do
    @moduledoc """
    A structural division in the TEI document (e.g., book, card, section).

    Textparts correspond to `<div type="textpart">` elements in the TEI XML
    and form a hierarchy identified by CTS URNs.
    """

    @type t :: %__MODULE__{
            depth: non_neg_integer(),
            index: non_neg_integer(),
            location: [String.t()],
            n: String.t() | nil,
            subtype: String.t() | nil,
            type: String.t() | nil,
            urn: String.t() | nil
          }

    @derive Jason.Encoder
    defstruct [:type, :subtype, :n, :index, :urn, :depth, location: []]
  end

  defmodule Element do
    @moduledoc """
    An inline element in the TEI document (e.g., `<p>`, `<note>`, `<milestone>`).

    Children can be `Kodon.TEIParser.TextRun` structs (character data) or
    nested `Kodon.TEIParser.Element` structs.
    """

    @type t :: %__MODULE__{
            tagname: String.t(),
            attrs: %{String.t() => String.t()},
            children: [t() | Kodon.TEIParser.TextRun.t()],
            index: non_neg_integer(),
            textpart_index: non_neg_integer() | nil,
            textpart_urn: String.t() | nil,
            urn: String.t() | nil
          }

    @derive Jason.Encoder
    defstruct [:tagname, :index, :textpart_index, :textpart_urn, :urn, attrs: %{}, children: []]
  end

  # --- Public struct ---

  @type t :: %__MODULE__{
          urn: String.t() | nil,
          language: String.t() | nil,
          textpart_labels: [String.t()],
          textparts: [Textpart.t()],
          elements: [Element.t()]
        }

  @derive Jason.Encoder
  defstruct urn: nil,
            language: nil,
            textpart_labels: [],
            textparts: [],
            elements: []

  # --- Nested structs ---

  defmodule TextRun do
    @moduledoc """
    A run of character data within an element.
    """

    @type t :: %__MODULE__{
            index: non_neg_integer(),
            text: String.t(),
            tokens: [Kodon.Tokenizer.Token.t()]
          }

    @derive Jason.Encoder
    defstruct [:index, :text, :tokens]
  end

  # --- Internal SAX state ---

  defmodule SaxState do
    @moduledoc false

    @type t :: %__MODULE__{
            current_textpart_location: [String.t()],
            current_textpart_urn: String.t() | nil,
            element_stack: [Kodon.TEIParser.Element.t()],
            elements: [Kodon.TEIParser.Element.t()],
            global_element_index: non_neg_integer(),
            in_body: boolean(),
            language: String.t() | nil,
            textpart_depth: non_neg_integer(),
            textpart_labels: [String.t()],
            textpart_stack: [Kodon.TEIParser.Textpart.t()],
            textparts: [Kodon.TEIParser.Textpart.t()],
            urn: String.t() | nil
          }

    defstruct current_textpart_location: [],
              current_textpart_urn: nil,
              element_stack: [],
              elements: [],
              global_element_index: 0,
              in_body: false,
              language: nil,
              textpart_depth: 0,
              textpart_labels: [],
              textpart_stack: [],
              textparts: [],
              urn: nil
  end

  # Elements we explicitly handle; others get a debug log
  @known_elements ~w[
    choice corr del foreign gap head hi l label lb lg
    milestone note num p pb q quote sic sp speaker
  ]

  # --- Public API ---

  @doc """
  Parse a TEI XML file into a `%TEIParser{}` struct.

  ## Example

      parsed = TEIParser.parse("path/to/tei.xml")
      parsed.urn
      #=> "urn:cts:greekLit:tlg0012.tlg001.perseus-eng4"
  """
  @spec parse(Path.t()) :: t()
  def parse(path) do
    path
    |> File.read!()
    |> parse_string()
  end

  @doc """
  Parse a TEI XML string into a `%TEIParser{}` struct.
  """
  @spec parse_string(String.t()) :: t()
  def parse_string(xml) do
    initial_state = %SaxState{}

    result =
      :xmerl_sax_parser.stream(
        String.to_charlist(xml),
        event_fun: &sax_event/3,
        event_state: initial_state
      )

    case result do
      {:ok, state, _rest} ->
        %__MODULE__{
          urn: state.urn,
          language: state.language,
          textpart_labels: state.textpart_labels,
          textparts: Enum.reverse(state.textparts),
          elements: Enum.reverse(state.elements)
        }

      {:fatal_error, location, reason, _end_tags, _state} ->
        raise "TEI XML parse error at #{inspect(location)}: #{inspect(reason)}"
    end
  end

  defmodule TableOfContentsEntry do
    @type t :: %__MODULE__{
            label: String.t(),
            subtype: String.t(),
            subpassages: [t()],
            urn: String.t()
          }

    defstruct [:label, :urn, :subtype, :subpassages]
  end

  @spec create_table_of_contents([Textpart.t()]) :: [TableOfContentsEntry.t()]
  def create_table_of_contents(textparts) do
    tps =
      textparts
      |> Enum.filter(fn tp -> tp.type == "textpart" end)
      |> Enum.map(fn tp ->
        n = Map.get(tp, :n)

        label =
          if is_nil(n) do
            String.capitalize(tp.subtype)
          else
            "#{String.capitalize(tp.subtype)} #{n}"
          end

        %{
          depth: tp.depth,
          index: tp.index,
          label: label,
          subpassages: [],
          subtype: tp.subtype,
          urn: tp.urn
        }
      end)

    case tps do
      [] ->
        tps

      _ ->
        max_depth =
          tps |> Enum.map(&Map.get(&1, :depth)) |> Enum.max()

        if max_depth < 2 do
          tps
        else
          nest_textparts(tps)
        end
    end
  end

  @spec nest_textparts(maybe_improper_list()) :: list()
  def nest_textparts([]), do: []

  def nest_textparts([item | rest]) do
    {children, remaining} = Enum.split_while(rest, &(&1.depth > item.depth))
    item = if children != [], do: %{item | subpassages: nest_textparts(children)}, else: item
    [item | nest_textparts(remaining)]
  end

  # --- Text extraction ---

  @doc """
  Extract base text from an element, excluding `<note>` elements.

  This is the primary method for getting the "reading text" of an element,
  stripping out editorial annotations and notes that would be displayed
  separately (e.g., in popovers or footnotes).

  ## Example

      # Given: <p>The anger <note>Greek: mēnis</note> of Achilles</p>
      TEIParser.base_text(p_element)
      #=> "The anger  of Achilles"
  """
  @spec base_text(Element.t() | TextRun.t()) :: String.t()
  def base_text(%Element{children: children}) do
    children
    |> Enum.reject(fn
      %Element{tagname: "note"} -> true
      _ -> false
    end)
    |> Enum.map(fn
      %TextRun{text: text} -> text
      %Element{} = el -> base_text(el)
    end)
    |> Enum.join()
  end

  def base_text(%TextRun{text: text}), do: text

  @doc """
  Extract all text from an element, including notes.
  """
  @spec full_text(Element.t() | TextRun.t()) :: String.t()
  def full_text(%Element{children: children}) do
    children
    |> Enum.map(fn
      %TextRun{text: text} -> Tokenizer.reconstruct(text)
      %Element{} = el -> full_text(el)
    end)
    |> Enum.join()
  end

  def full_text(%TextRun{text: text}), do: Tokenizer.reconstruct(text)

  # --- Query helpers ---

  @doc """
  Get all top-level elements belonging to a specific textpart, identified by URN.
  """
  @spec elements_for_textpart(t(), String.t()) :: [Element.t()]
  def elements_for_textpart(%__MODULE__{elements: elements}, textpart_urn)
      when is_binary(textpart_urn) do
    Enum.filter(elements, &(&1.textpart_urn == textpart_urn))
  end

  @doc """
  Get all top-level elements belonging to a specific textpart, identified by index.
  """
  @spec elements_for_textpart_index(t(), non_neg_integer()) :: [Element.t()]
  def elements_for_textpart_index(%__MODULE__{elements: elements}, textpart_index)
      when is_integer(textpart_index) do
    Enum.filter(elements, &(&1.textpart_index == textpart_index))
  end

  @doc """
  Find all descendant elements with a given tag name within an element's children.
  """
  @spec find_child_elements(Element.t(), String.t()) :: [Element.t()]
  def find_child_elements(%Element{children: children}, tagname) do
    Enum.flat_map(children, fn
      %Element{tagname: ^tagname} = el ->
        [el | find_child_elements(el, tagname)]

      %Element{} = el ->
        find_child_elements(el, tagname)

      %TextRun{} ->
        []
    end)
  end

  @doc """
  Collapse whitespace in text: replace all whitespace sequences with a single space
  and trim leading/trailing whitespace.
  """
  @spec collapse_whitespace(String.t()) :: String.t()
  def collapse_whitespace(text) when is_binary(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  # --- SAX event handler ---

  defp sax_event({:startElement, _uri, localname_chars, _qname, attrs}, _location, state) do
    localname = to_string(localname_chars)

    cond do
      localname == "body" ->
        %{state | in_body: true}

      not state.in_body ->
        state

      true ->
        clean_attrs = clean_attributes(attrs)
        handle_start_element(state, localname, clean_attrs)
    end
  end

  defp sax_event({:endElement, _uri, localname_chars, _qname}, _location, state) do
    localname = to_string(localname_chars)

    cond do
      localname == "body" ->
        %{state | in_body: false}

      not state.in_body ->
        state

      true ->
        handle_end_element(state, localname)
    end
  end

  defp sax_event({:characters, chars}, _location, %SaxState{in_body: true} = state) do
    handle_characters(state, to_string(chars))
  end

  defp sax_event(_event, _location, state), do: state

  # --- Start element handling ---

  defp handle_start_element(state, "div", attrs) do
    handle_div(state, attrs)
  end

  defp handle_start_element(state, tagname, attrs) do
    if tagname not in @known_elements do
      Logger.debug("#{state.urn}\nUnknown element: #{tagname} in #{state.current_textpart_urn}")
    end

    handle_element(state, tagname, attrs)
  end

  defp handle_div(state, attrs) do
    case Map.get(attrs, "type") do
      type when type in ["edition", "translation"] ->
        # Record edition metadata, then push an implicit textpart so that content
        # not further subdivided into textparts (e.g. hymns) is still captured.
        state = %{state | language: attrs["lang"], urn: attrs["n"]}
        push_edition_textpart(state, attrs)

      "textpart" ->
        add_textpart_to_stack(state, attrs)

      _ ->
        state
    end
  end

  defp push_edition_textpart(state, attrs) do
    textpart = %Textpart{
      # pushing the main container as a textpart
      # is a bit of a hack, so we set depth to 0
      # to avoid having to make further adjustments
      # when there are proper textparts in the XML.
      depth: 0,
      index: length(state.textpart_stack) + length(state.textparts),
      location: [],
      n: nil,
      subtype: nil,
      type: attrs["type"],
      urn: state.urn
    }

    %{
      state
      | textpart_stack: [textpart | state.textpart_stack],
        current_textpart_location: [],
        current_textpart_urn: state.urn
    }
  end

  defp add_textpart_to_stack(state, attrs) do
    subtype = attrs["subtype"]

    textpart_labels =
      if subtype && subtype not in state.textpart_labels do
        state.textpart_labels ++ [subtype]
      else
        state.textpart_labels
      end

    location = determine_location(state, attrs)
    urn = if state.urn, do: "#{state.urn}:#{Enum.join(location, ".")}", else: nil

    textpart_depth = state.textpart_depth + 1

    textpart = %Textpart{
      depth: textpart_depth,
      index: length(state.textpart_stack) + length(state.textparts),
      location: location,
      n: attrs["n"],
      subtype: subtype,
      type: attrs["type"],
      urn: urn
    }

    %{
      state
      | textpart_depth: textpart_depth,
        textpart_labels: textpart_labels,
        textpart_stack: [textpart | state.textpart_stack],
        current_textpart_location: location,
        current_textpart_urn: urn
    }
  end

  defp determine_location(state, attrs) do
    citation_n = attrs["n"]

    parent_ns =
      state.textpart_stack
      |> Enum.reverse()
      |> Enum.flat_map(fn tp -> if tp.n, do: [tp.n], else: [] end)

    if citation_n, do: parent_ns ++ [citation_n], else: parent_ns
  end

  defp handle_element(state, tagname, attrs) do
    textpart =
      case state.textpart_stack do
        [tp | _] ->
          tp

        [] ->
          Logger.warning("#{state.urn}\nElement outside textpart: #{tagname}, #{inspect(attrs)}")

          case state.textparts do
            [tp | _] -> tp
            [] -> nil
          end
      end

    case textpart do
      nil ->
        Logger.warning("#{state.urn}\nOrphaned element: #{tagname} — no textpart available.")

        state

      tp ->
        urn_element_index =
          count_matching_elements(state.elements, state.current_textpart_urn, tagname) +
            count_matching_elements(state.element_stack, state.current_textpart_urn, tagname)

        element = %Element{
          tagname: tagname,
          attrs: attrs,
          children: [],
          index: state.global_element_index,
          textpart_index: tp.index,
          textpart_urn: state.current_textpart_urn,
          urn: "#{state.current_textpart_urn}@<#{tagname}>[#{urn_element_index}]"
        }

        %{
          state
          | element_stack: [element | state.element_stack],
            global_element_index: state.global_element_index + 1
        }
    end
  end

  defp count_matching_elements(elements, textpart_urn, tagname) do
    Enum.count(elements, fn el ->
      el.textpart_urn == textpart_urn && el.tagname == tagname
    end)
  end

  # --- End element handling ---

  defp handle_end_element(state, "div") do
    case state.textpart_stack do
      [textpart | rest] ->
        {parent_location, parent_urn} =
          case rest do
            [parent | _] -> {parent.location, parent.urn}
            [] -> {[], nil}
          end

        %{
          state
          | textpart_depth: state.textpart_depth - 1,
            textpart_stack: rest,
            textparts: [textpart | state.textparts],
            current_textpart_location: parent_location,
            current_textpart_urn: parent_urn
        }

      [] ->
        # Non-textpart div (like edition div), nothing to pop
        state
    end
  end

  defp handle_end_element(state, _tagname) do
    case state.element_stack do
      [el | rest] ->
        el = %{el | urn: el.urn || state.current_textpart_urn}

        case rest do
          [parent | rest_stack] ->
            # Add completed child element to parent's children
            parent = %{parent | children: parent.children ++ [el]}
            %{state | element_stack: [parent | rest_stack]}

          [] ->
            # Top-level element (no parent element), add to elements list
            %{state | element_stack: [], elements: [el | state.elements]}
        end

      [] ->
        state
    end
  end

  # --- Characters handling ---

  defp handle_characters(state, text) do
    case state.element_stack do
      [] ->
        if String.trim(text) != "" do
          Logger.warning("#{state.urn}\nCharacters outside elements: #{inspect(text)}")
        end

        state

      [parent | rest] ->
        text_run = %TextRun{
          text: text,
          index: state.global_element_index,
          tokens: Tokenizer.tokenize(text)
        }

        parent = %{parent | children: parent.children ++ [text_run]}

        %{
          state
          | element_stack: [parent | rest],
            global_element_index: state.global_element_index + 1
        }
    end
  end

  # --- Attribute helpers ---

  defp clean_attributes(attrs) do
    Enum.into(attrs, %{}, fn {_uri, _prefix, localname, value} ->
      {to_string(localname), to_string(value)}
    end)
  end
end
