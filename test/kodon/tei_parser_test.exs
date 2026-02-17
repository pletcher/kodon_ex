defmodule Kodon.TEIParserTest do
  use ExUnit.Case, async: true

  alias Kodon.TEIParser
  alias Kodon.TEIParser.{Element, TextRun}

  @fixtures_dir Path.expand("../fixtures", __DIR__)

  # --- Parsing book/card/milestone format ---

  describe "parse/1 with book_card_milestone format" do
    setup do
      parsed = TEIParser.parse(Path.join(@fixtures_dir, "tei_book_card_milestone.xml"))
      %{parsed: parsed}
    end

    test "extracts URN from edition div", %{parsed: parsed} do
      assert parsed.urn == "urn:cts:greekLit:tlg0012.tlg001.test-eng1"
    end

    test "extracts language from edition div", %{parsed: parsed} do
      assert parsed.language == "eng"
    end

    test "discovers textpart labels in order", %{parsed: parsed} do
      assert parsed.textpart_labels == ["book", "card"]
    end

    test "collects all textparts", %{parsed: parsed} do
      # 2 books + 3 cards = 5 textparts
      assert length(parsed.textparts) == 5
    end

    test "assigns correct subtypes and locations to textparts", %{parsed: parsed} do
      books = Enum.filter(parsed.textparts, &(&1.subtype == "book"))
      cards = Enum.filter(parsed.textparts, &(&1.subtype == "card"))

      assert length(books) == 2
      assert length(cards) == 3

      book1 = Enum.find(books, &(&1.n == "1"))
      assert book1.location == ["1"]
      assert book1.urn == "urn:cts:greekLit:tlg0012.tlg001.test-eng1:1"

      book2 = Enum.find(books, &(&1.n == "2"))
      assert book2.location == ["2"]
    end

    test "assigns correct URNs to card textparts", %{parsed: parsed} do
      cards = Enum.filter(parsed.textparts, &(&1.subtype == "card"))

      card_1_1 = Enum.find(cards, &(&1.location == ["1", "1"]))
      assert card_1_1.urn == "urn:cts:greekLit:tlg0012.tlg001.test-eng1:1.1"

      card_1_2 = Enum.find(cards, &(&1.location == ["1", "2"]))
      assert card_1_2.urn == "urn:cts:greekLit:tlg0012.tlg001.test-eng1:1.2"
    end

    test "parses paragraph elements with milestones", %{parsed: parsed} do
      # Each <p> is a top-level element
      p_elements = Enum.filter(parsed.elements, &(&1.tagname == "p"))
      assert length(p_elements) == 4
    end

    test "milestones are children of paragraph elements", %{parsed: parsed} do
      p = hd(parsed.elements)
      milestones = Enum.filter(p.children, fn
        %Element{tagname: "milestone"} -> true
        _ -> false
      end)

      assert length(milestones) == 1
      [milestone] = milestones
      assert milestone.attrs["unit"] == "line"
      assert milestone.attrs["n"] == "1"
    end

    test "paragraph text is preserved as TextRun children", %{parsed: parsed} do
      p = hd(parsed.elements)
      text = TEIParser.collapse_whitespace(TEIParser.base_text(p))

      assert text =~ "Sing, O goddess"
      assert text =~ "countless ills upon the Achaeans"
    end
  end

  # --- Parsing line elements format ---

  describe "parse/1 with line_elements format" do
    setup do
      parsed = TEIParser.parse(Path.join(@fixtures_dir, "tei_line_elements.xml"))
      %{parsed: parsed}
    end

    test "extracts URN", %{parsed: parsed} do
      assert parsed.urn == "urn:cts:greekLit:tlg0013.tlg003.test-eng1"
    end

    test "parses head element", %{parsed: parsed} do
      heads = Enum.filter(parsed.elements, &(&1.tagname == "head"))
      assert length(heads) == 1
      [head] = heads
      assert TEIParser.full_text(head) == "To Dionysus"
    end

    test "parses line elements with n attributes", %{parsed: parsed} do
      lines = Enum.filter(parsed.elements, &(&1.tagname == "l"))
      assert length(lines) == 3

      first_line = Enum.find(lines, &(&1.attrs["n"] == "1"))
      assert TEIParser.base_text(first_line) =~ "Dionysus"
    end

    test "collects section textpart", %{parsed: parsed} do
      sections = Enum.filter(parsed.textparts, &(&1.subtype == "section"))
      assert length(sections) == 1
    end
  end

  # --- Inline notes (the key bug fix) ---

  describe "parse/1 with inline notes" do
    setup do
      parsed = TEIParser.parse(Path.join(@fixtures_dir, "tei_with_notes.xml"))
      %{parsed: parsed}
    end

    test "base_text excludes note content", %{parsed: parsed} do
      p = hd(parsed.elements)
      base = TEIParser.collapse_whitespace(TEIParser.base_text(p))

      assert base =~ "Sing, O goddess, the anger"
      assert base =~ "of Achilles son of Peleus"
      # Note content should NOT be in base text
      refute base =~ "μῆνιν"
      refute base =~ "Greek:"
    end

    test "full_text includes note content", %{parsed: parsed} do
      p = hd(parsed.elements)
      full = TEIParser.full_text(p)

      assert full =~ "Sing, O goddess, the anger"
      assert full =~ "μῆνιν"
      assert full =~ "of Achilles son of Peleus"
    end

    test "notes are preserved as child elements of paragraphs", %{parsed: parsed} do
      p = hd(parsed.elements)
      notes = Enum.filter(p.children, fn
        %Element{tagname: "note"} -> true
        _ -> false
      end)

      assert length(notes) == 1
    end

    test "notes can contain nested elements like foreign", %{parsed: parsed} do
      p = hd(parsed.elements)
      [note] = Enum.filter(p.children, fn
        %Element{tagname: "note"} -> true
        _ -> false
      end)

      foreign_elements = TEIParser.find_child_elements(note, "foreign")
      assert length(foreign_elements) == 1

      [foreign] = foreign_elements
      assert foreign.attrs["lang"] == "grc"
      assert TEIParser.full_text(foreign) == "μῆνιν"
    end

    test "second paragraph also separates notes from base text", %{parsed: parsed} do
      paragraphs = Enum.filter(parsed.elements, &(&1.tagname == "p"))
      second_p = Enum.at(paragraphs, 1)

      base = TEIParser.collapse_whitespace(TEIParser.base_text(second_p))
      assert base =~ "Many a brave soul"
      assert base =~ "did it send hurrying down to Hades"
      refute base =~ "ψυχή"

      full = TEIParser.full_text(second_p)
      assert full =~ "ψυχή"
    end
  end

  # --- parse_string/1 ---

  describe "parse_string/1" do
    test "parses minimal TEI XML" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <TEI xmlns="http://www.tei-c.org/ns/1.0">
        <teiHeader><fileDesc><titleStmt><title>T</title></titleStmt>
        <publicationStmt><p/></publicationStmt><sourceDesc><p/></sourceDesc></fileDesc></teiHeader>
        <text><body>
          <div type="edition" n="urn:test" xml:lang="grc">
            <div type="textpart" subtype="section" n="1">
              <p>Hello world</p>
            </div>
          </div>
        </body></text>
      </TEI>
      """

      parsed = TEIParser.parse_string(xml)
      assert parsed.urn == "urn:test"
      assert parsed.language == "grc"
      assert length(parsed.textparts) == 1
      assert length(parsed.elements) == 1

      [p] = parsed.elements
      assert p.tagname == "p"
      assert TEIParser.collapse_whitespace(TEIParser.base_text(p)) == "Hello world"
    end

    test "handles self-closing elements" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <TEI xmlns="http://www.tei-c.org/ns/1.0">
        <teiHeader><fileDesc><titleStmt><title>T</title></titleStmt>
        <publicationStmt><p/></publicationStmt><sourceDesc><p/></sourceDesc></fileDesc></teiHeader>
        <text><body>
          <div type="edition" n="urn:test" xml:lang="eng">
            <div type="textpart" subtype="section" n="1">
              <p><milestone unit="line" n="42"/>Some text</p>
            </div>
          </div>
        </body></text>
      </TEI>
      """

      parsed = TEIParser.parse_string(xml)
      [p] = parsed.elements

      milestones = Enum.filter(p.children, fn
        %Element{tagname: "milestone"} -> true
        _ -> false
      end)

      assert length(milestones) == 1
      [ms] = milestones
      assert ms.attrs["n"] == "42"
      assert ms.children == []
    end

    test "ignores content outside body" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <TEI xmlns="http://www.tei-c.org/ns/1.0">
        <teiHeader><fileDesc><titleStmt><title>Header Title</title></titleStmt>
        <publicationStmt><p/></publicationStmt><sourceDesc><p/></sourceDesc></fileDesc></teiHeader>
        <text><body>
          <div type="edition" n="urn:test" xml:lang="eng">
            <div type="textpart" subtype="section" n="1">
              <p>Body text</p>
            </div>
          </div>
        </body></text>
      </TEI>
      """

      parsed = TEIParser.parse_string(xml)

      # "Header Title" should not appear in any element
      all_text =
        parsed.elements
        |> Enum.map(&TEIParser.full_text/1)
        |> Enum.join(" ")

      refute all_text =~ "Header Title"
      assert all_text =~ "Body text"
    end
  end

  # --- Text extraction ---

  describe "base_text/1 and full_text/1" do
    test "base_text on TextRun returns text" do
      tr = %TextRun{text: "hello", index: 0}
      assert TEIParser.base_text(tr) == "hello"
    end

    test "full_text on TextRun returns text" do
      tr = %TextRun{text: "hello", index: 0}
      assert TEIParser.full_text(tr) == "hello"
    end

    test "base_text on element with only TextRun children" do
      el = %Element{
        tagname: "p",
        index: 0,
        children: [
          %TextRun{text: "Hello ", index: 1},
          %TextRun{text: "world", index: 2}
        ]
      }

      assert TEIParser.base_text(el) == "Hello world"
    end

    test "base_text excludes note elements" do
      el = %Element{
        tagname: "p",
        index: 0,
        children: [
          %TextRun{text: "Before ", index: 1},
          %Element{
            tagname: "note",
            index: 2,
            children: [%TextRun{text: "note content", index: 3}]
          },
          %TextRun{text: " after", index: 4}
        ]
      }

      assert TEIParser.base_text(el) == "Before  after"
    end

    test "full_text includes note elements" do
      el = %Element{
        tagname: "p",
        index: 0,
        children: [
          %TextRun{text: "Before ", index: 1},
          %Element{
            tagname: "note",
            index: 2,
            children: [%TextRun{text: "note content", index: 3}]
          },
          %TextRun{text: " after", index: 4}
        ]
      }

      assert TEIParser.full_text(el) == "Before note content after"
    end

    test "base_text recursively processes non-note child elements" do
      el = %Element{
        tagname: "p",
        index: 0,
        children: [
          %TextRun{text: "Start ", index: 1},
          %Element{
            tagname: "hi",
            index: 2,
            children: [%TextRun{text: "emphasized", index: 3}]
          },
          %TextRun{text: " end", index: 4}
        ]
      }

      assert TEIParser.base_text(el) == "Start emphasized end"
    end
  end

  # --- Query helpers ---

  describe "elements_for_textpart/2" do
    test "filters elements by textpart URN" do
      parsed = %TEIParser{
        elements: [
          %Element{tagname: "p", index: 0, textpart_urn: "urn:1"},
          %Element{tagname: "p", index: 1, textpart_urn: "urn:2"},
          %Element{tagname: "p", index: 2, textpart_urn: "urn:1"}
        ]
      }

      result = TEIParser.elements_for_textpart(parsed, "urn:1")
      assert length(result) == 2
      assert Enum.all?(result, &(&1.textpart_urn == "urn:1"))
    end
  end

  describe "elements_for_textpart_index/2" do
    test "filters elements by textpart index" do
      parsed = %TEIParser{
        elements: [
          %Element{tagname: "p", index: 0, textpart_index: 0},
          %Element{tagname: "p", index: 1, textpart_index: 1},
          %Element{tagname: "p", index: 2, textpart_index: 0}
        ]
      }

      result = TEIParser.elements_for_textpart_index(parsed, 0)
      assert length(result) == 2
    end
  end

  describe "find_child_elements/2" do
    test "finds direct child elements" do
      el = %Element{
        tagname: "p",
        index: 0,
        children: [
          %TextRun{text: "text", index: 1},
          %Element{tagname: "note", index: 2, children: []},
          %Element{tagname: "hi", index: 3, children: []}
        ]
      }

      notes = TEIParser.find_child_elements(el, "note")
      assert length(notes) == 1
    end

    test "finds deeply nested elements" do
      el = %Element{
        tagname: "p",
        index: 0,
        children: [
          %Element{
            tagname: "note",
            index: 1,
            children: [
              %Element{
                tagname: "foreign",
                index: 2,
                children: [%TextRun{text: "μῆνιν", index: 3}]
              }
            ]
          }
        ]
      }

      foreign = TEIParser.find_child_elements(el, "foreign")
      assert length(foreign) == 1
      assert TEIParser.full_text(hd(foreign)) == "μῆνιν"
    end
  end

  # --- URN generation ---

  describe "URN generation" do
    test "textpart URNs follow CTS convention" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <TEI xmlns="http://www.tei-c.org/ns/1.0">
        <teiHeader><fileDesc><titleStmt><title>T</title></titleStmt>
        <publicationStmt><p/></publicationStmt><sourceDesc><p/></sourceDesc></fileDesc></teiHeader>
        <text><body>
          <div type="edition" n="urn:cts:greekLit:tlg0012.tlg001.perseus-eng4" xml:lang="eng">
            <div type="textpart" subtype="book" n="3">
              <div type="textpart" subtype="card" n="5">
                <p>Text</p>
              </div>
            </div>
          </div>
        </body></text>
      </TEI>
      """

      parsed = TEIParser.parse_string(xml)

      book = Enum.find(parsed.textparts, &(&1.subtype == "book"))
      assert book.urn == "urn:cts:greekLit:tlg0012.tlg001.perseus-eng4:3"

      card = Enum.find(parsed.textparts, &(&1.subtype == "card"))
      assert card.urn == "urn:cts:greekLit:tlg0012.tlg001.perseus-eng4:3.5"
    end

    test "element URNs include tagname and index" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <TEI xmlns="http://www.tei-c.org/ns/1.0">
        <teiHeader><fileDesc><titleStmt><title>T</title></titleStmt>
        <publicationStmt><p/></publicationStmt><sourceDesc><p/></sourceDesc></fileDesc></teiHeader>
        <text><body>
          <div type="edition" n="urn:test" xml:lang="eng">
            <div type="textpart" subtype="section" n="1">
              <p>First para</p>
              <p>Second para</p>
            </div>
          </div>
        </body></text>
      </TEI>
      """

      parsed = TEIParser.parse_string(xml)
      paragraphs = Enum.filter(parsed.elements, &(&1.tagname == "p"))

      assert length(paragraphs) == 2
      [p1, p2] = paragraphs
      assert p1.urn == "urn:test:1@<p>[0]"
      assert p2.urn == "urn:test:1@<p>[1]"
    end
  end

  # --- Legacy helpers ---

  describe "collapse_whitespace/1" do
    test "collapses internal whitespace" do
      assert TEIParser.collapse_whitespace("  hello   world  ") == "hello world"
    end

    test "handles newlines and tabs" do
      assert TEIParser.collapse_whitespace("hello\n\t  world") == "hello world"
    end
  end
end
