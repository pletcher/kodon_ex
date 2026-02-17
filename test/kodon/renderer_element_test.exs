defmodule Kodon.RendererElementTest do
  use ExUnit.Case, async: true

  alias Kodon.Renderer
  alias Kodon.TEIParser.{Element, TextRun}

  describe "render_element/1 with TextRun" do
    test "renders plain text with HTML escaping" do
      tr = %TextRun{text: "Hello world", index: 0}
      result = Renderer.render_element(tr)
      assert result =~ "Hello world"
    end

    test "escapes HTML entities in text" do
      tr = %TextRun{text: "A < B & C > D", index: 0}
      result = Renderer.render_element(tr)
      assert result =~ "A &lt; B &amp; C &gt; D"
    end
  end

  describe "render_element/1 with Element" do
    test "renders nested elements" do
      el = %Element{
        tagname: "p",
        index: 0,
        children: [
          %Element{
            tagname: "foreign",
            attrs: %{"lang" => "grc"},
            children: [%TextRun{text: "μῆνιν", index: 1}],
            index: 2
          }
        ]
      }

      result = Renderer.render_element(el)

      assert result =~ "<p>"
      assert result =~ ~s(lang="grc")
      assert result =~ ~s(class="foreign")
      assert result =~ "μῆνιν"
    end

    test "renders <p> element" do
      el = %Element{
        tagname: "p",
        index: 0,
        children: [%TextRun{text: "Hello", index: 1}]
      }

      result = Renderer.render_element(el)
      assert result =~ "<p>"
      assert result =~ "Hello"
      assert result =~ "</p>"
    end

    test "renders <head> element as h2" do
      el = %Element{
        tagname: "head",
        index: 0,
        children: [%TextRun{text: "Title", index: 1}]
      }

      result = Renderer.render_element(el)
      assert result =~ ~s(<h2 class="section-head">)
      assert result =~ "Title"
      assert result =~ "</h2>"
    end

    test "renders <hi> element as em" do
      el = %Element{
        tagname: "hi",
        index: 0,
        children: [%TextRun{text: "emphasized", index: 1}]
      }

      result = Renderer.render_element(el)
      assert result =~ "<em>"
      assert result =~ "emphasized"
      assert result =~ "</em>"
    end

    test "renders <foreign> element with lang attribute" do
      el = %Element{
        tagname: "foreign",
        index: 0,
        attrs: %{"lang" => "grc"},
        children: [%TextRun{text: "μῆνιν", index: 1}]
      }

      result = Renderer.render_element(el)
      assert result =~ ~s(lang="grc")
      assert result =~ ~s(class="foreign")
      assert result =~ "μῆνιν"
    end

    test "renders <milestone> with unit=line" do
      el = %Element{
        tagname: "milestone",
        index: 0,
        attrs: %{"unit" => "line", "n" => "42"},
        children: []
      }

      result = Renderer.render_element(el)
      assert result =~ ~s(id="milestone-42")
      assert result =~ ~s(class="milestone")
    end

    test "renders <milestone> without unit=line as empty" do
      el = %Element{
        tagname: "milestone",
        index: 0,
        attrs: %{"unit" => "para", "n" => "1"},
        children: []
      }

      result = Renderer.render_element(el)
      refute result =~ "milestone"
    end

    test "renders <l> element with line number" do
      el = %Element{
        tagname: "l",
        index: 0,
        attrs: %{"n" => "5"},
        children: [%TextRun{text: "Line five text", index: 1}]
      }

      result = Renderer.render_element(el)
      assert result =~ ~s(class="line")
      assert result =~ ~s(class="line-number")
      assert result =~ "5"
      assert result =~ "Line five text"
    end

    test "renders <note> element as annotation popover" do
      el = %Element{
        tagname: "note",
        index: 0,
        children: [%TextRun{text: "A scholarly note", index: 1}]
      }

      result = Renderer.render_element(el)
      assert result =~ "annotation"
      assert result =~ "A scholarly note"
    end

    test "renders <q> element" do
      el = %Element{
        tagname: "q",
        index: 0,
        children: [%TextRun{text: "quoted text", index: 1}]
      }

      result = Renderer.render_element(el)
      assert result =~ "<q>"
      assert result =~ "quoted text"
      assert result =~ "</q>"
    end

    test "renders <quote> element as blockquote" do
      el = %Element{
        tagname: "quote",
        index: 0,
        children: [%TextRun{text: "block quoted", index: 1}]
      }

      result = Renderer.render_element(el)
      assert result =~ "<blockquote>"
      assert result =~ "block quoted"
      assert result =~ "</blockquote>"
    end

    test "renders <lg> element" do
      el = %Element{
        tagname: "lg",
        index: 0,
        children: [%TextRun{text: "lines", index: 1}]
      }

      result = Renderer.render_element(el)
      assert result =~ ~s(class="line-group")
      assert result =~ "lines"
    end

    test "renders <lb> as br" do
      el = %Element{
        tagname: "lb",
        index: 0,
        children: []
      }

      result = Renderer.render_element(el)
      assert result =~ "<br/>"
    end

    test "renders unknown element with default template" do
      el = %Element{
        tagname: "speaker",
        index: 0,
        children: [%TextRun{text: "Achilles", index: 1}]
      }

      result = Renderer.render_element(el)
      assert result =~ ~s(class="tei-speaker")
      assert result =~ "Achilles"
    end
  end

  describe "render_children/1" do
    test "renders a list of mixed children" do
      children = [
        %TextRun{text: "Before ", index: 0},
        %Element{
          tagname: "hi",
          index: 1,
          children: [%TextRun{text: "bold", index: 2}]
        },
        %TextRun{text: " after", index: 3}
      ]

      result = Renderer.render_children(children)
      assert result =~ "Before "
      assert result =~ "<em>"
      assert result =~ "bold"
      assert result =~ "</em>"
      assert result =~ " after"
    end

    test "renders nested elements recursively" do
      children = [
        %Element{
          tagname: "p",
          index: 0,
          children: [
            %TextRun{text: "Text with ", index: 1},
            %Element{
              tagname: "foreign",
              index: 2,
              attrs: %{"lang" => "grc"},
              children: [%TextRun{text: "μῆνιν", index: 3}]
            },
            %TextRun{text: " inline", index: 4}
          ]
        }
      ]

      result = Renderer.render_children(children)
      assert result =~ "<p>"
      assert result =~ "Text with "
      assert result =~ ~s(lang="grc")
      assert result =~ "μῆνιν"
      assert result =~ " inline"
      assert result =~ "</p>"
    end

    test "renders empty list" do
      assert Renderer.render_children([]) == ""
    end
  end

  describe "resolve_template_path/1" do
    test "resolves known element templates" do
      path = Renderer.resolve_template_path(Path.join("elements", "p.eex"))
      assert File.exists?(path)
      assert String.ends_with?(path, "elements/p.eex")
    end

    test "falls back to default.eex for unknown elements" do
      path = Renderer.resolve_template_path(Path.join("elements", "nonexistent_tag.eex"))
      assert File.exists?(path)
      assert String.ends_with?(path, "elements/default.eex")
    end

    test "resolves page-level templates" do
      path = Renderer.resolve_template_path("layout.eex")
      assert File.exists?(path)
      assert String.ends_with?(path, "layout.eex")
    end
  end

  describe "text utilities" do
    test "escape_html/1 escapes special characters" do
      assert Renderer.escape_html("<div>") == "&lt;div&gt;"
      assert Renderer.escape_html("a & b") == "a &amp; b"
      assert Renderer.escape_html(~s("quoted")) == "&quot;quoted&quot;"
    end

    test "macronize/1 converts macron markers" do
      assert Renderer.macronize("me&gt;nis") == "mēnis"
      assert Renderer.macronize("e&gt;") == "ē"
      assert Renderer.macronize("o&gt;") == "ō"
    end
  end
end
