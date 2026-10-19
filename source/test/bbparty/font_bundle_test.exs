defmodule Bbparty.FontBundleTest do
  use ExUnit.Case, async: true

  alias Bbparty.FontBundle

  defp entry(name, overrides \\ %{}) do
    Map.merge(
      %{
        "name" => name,
        "source_id" => "families/x/#{name}",
        "file" => "files/families_x_#{String.replace(name, " ", "-")}.woff2",
        "features" => ["liga", "kern"]
      },
      overrides
    )
  end

  defp fonts!(entries) do
    {:ok, fonts} = FontBundle.fonts(%{"fonts" => entries})
    fonts
  end

  describe "fonts/1 — identity" do
    test "the id and family are the exported name, byte for byte" do
      [font] = fonts!([entry("Boogy Brut Light Italic")])

      assert font.id == "Boogy Brut Light Italic"
      assert font.family == "Boogy Brut Light Italic"
    end

    test "a name is never normalised: accents, case and inner spacing survive" do
      names = ["Àpre  Regular", "BBWB", "matorral bold"]

      entries =
        names
        |> Enum.with_index()
        |> Enum.map(fn {name, i} -> entry(name, %{"file" => "files/f#{i}.woff2"}) end)

      assert Enum.map(fonts!(entries), & &1.id) == Enum.sort(names)
    end

    test "only the basename of the file is kept, and the export path is remembered" do
      [font] = fonts!([entry("A", %{"file" => "files/families_a_a.woff2"})])

      assert font.file == "families_a_a.woff2"
      assert font.source == "files/families_a_a.woff2"
    end

    test "features are kept whole, deduplicated and sorted" do
      [font] = fonts!([entry("A", %{"features" => ["ss01", "aalt", "kern", "ss01"]})])

      assert font.features == ["aalt", "kern", "ss01"]
    end

    test "fonts come back sorted by id whatever the export order" do
      assert Enum.map(fonts!([entry("C"), entry("A"), entry("B")]), & &1.id) == ["A", "B", "C"]
    end
  end

  describe "fonts/1 — refusals" do
    test "a name longer than a tag holds is refused; exactly the limit is fine" do
      at_limit = String.duplicate("a", FontBundle.max_id_bytes())
      over = String.duplicate("a", FontBundle.max_id_bytes() + 1)

      assert {:ok, [_]} = FontBundle.fonts(%{"fonts" => [entry(at_limit)]})

      assert {:error, [{:too_long, ^over, 47}]} =
               FontBundle.fonts(%{"fonts" => [entry(over)]})
    end

    test "the limit counts bytes, not characters" do
      name = String.duplicate("é", 24)

      assert {:error, [{:too_long, ^name, 48}]} = FontBundle.fonts(%{"fonts" => [entry(name)]})
    end

    test "two fonts with the same name are refused" do
      assert {:error, [{:duplicate, "Brut Regular", 2}]} =
               FontBundle.fonts(%{
                 "fonts" => [
                   entry("Brut Regular", %{"file" => "files/a.woff2"}),
                   entry("Brut Regular", %{"file" => "files/b.woff2"})
                 ]
               })
    end

    test "a file name that is not a plain .woff2 is refused" do
      for file <- ["files/a font.woff2", "files/a.otf", "files/../../x\".woff2"] do
        assert {:error, [{:bad_file, "A", ^file}]} =
                 FontBundle.fonts(%{"fonts" => [entry("A", %{"file" => file})]})
      end
    end

    test "every problem is collected in one pass" do
      over = String.duplicate("b", 50)

      assert {:error, problems} =
               FontBundle.fonts(%{
                 "fonts" => [
                   entry(over),
                   entry("", %{}),
                   %{"name" => "no file"},
                   entry("C", %{"features" => [1]})
                 ]
               })

      assert length(problems) == 4
    end

    test "a document that is not an export is refused" do
      assert {:error, [{:malformed, %{"nope" => 1}}]} = FontBundle.fonts(%{"nope" => 1})
    end
  end

  describe "manifest_json/1" do
    test "decodes to the FontMap shape, without the export path" do
      fonts = fonts!([entry("B"), entry("A")])
      decoded = fonts |> FontBundle.manifest_json() |> Jason.decode!()

      assert [
               %{
                 "id" => "A",
                 "family" => "A",
                 "file" => "families_x_A.woff2",
                 "features" => ["kern", "liga"]
               },
               %{"id" => "B"}
             ] = decoded["fonts"]

      refute Map.has_key?(hd(decoded["fonts"]), "source")
    end

    test "is identical for the same fonts in any export order" do
      a = FontBundle.manifest_json(fonts!([entry("A"), entry("B")]))
      b = FontBundle.manifest_json(fonts!([entry("B"), entry("A")]))

      assert a == b
    end
  end

  describe "font_faces_css/1" do
    test "one face per font, family quoted, served from /fonts/, blocking display" do
      css = FontBundle.font_faces_css(fonts!([entry("Boogy Brut Bold")]))

      assert css =~ ~s(font-family: "Boogy Brut Bold";)
      assert css =~ ~s|src: url("/fonts/families_x_Boogy-Brut-Bold.woff2") format("woff2");|
      assert css =~ "font-display: block;"
      assert length(String.split(css, "@font-face")) == 2
    end

    test "escapes quotes and backslashes in a family" do
      css =
        FontBundle.font_faces_css(fonts!([entry(~s(A "B" \\C), %{"file" => "files/abc.woff2"})]))

      assert css =~ ~s(font-family: "A \\"B\\" \\\\C";)
    end
  end

  describe "font_faces_css/1 — the pinned faces" do
    defp pin(family), do: Enum.find(FontBundle.pins(), &(&1.family == family))

    test "each pin is served from its own source's file, restricted to its range" do
      for pin <- FontBundle.pins() do
        css = FontBundle.font_faces_css(fonts!([entry(pin.source)]))
        file = "families_x_" <> String.replace(pin.source, " ", "-") <> ".woff2"

        assert css =~ ~s(font-family: "#{pin.family}";)
        assert css =~ "unicode-range: #{pin.ranges};"
        assert css =~ ~s|src: url("/fonts/#{file}") format("woff2");|
      end
    end

    test "the pins claim exactly the codepoints they are meant to" do
      assert pin("BB Emoji").ranges == "U+1F600-1F64F, U+1F900-1F9FF"
      assert pin("BB Emoji").source == "Boogy Brut Regular"
      assert pin("BB Apple").ranges == "U+F8FF"
      assert pin("BB Apple").source == "Brut Grotesque Medium"
    end

    test "pinned_families/0 is the order font-family must start with" do
      assert FontBundle.pinned_families() == ["BB Emoji", "BB Apple"]
    end

    test "a pin is omitted, rather than dangling, when its source is absent" do
      fonts = fonts!([entry("Traulha Regulara")])
      css = FontBundle.font_faces_css(fonts)

      assert FontBundle.missing_pin_sources(fonts) == FontBundle.pin_sources()

      for family <- FontBundle.pinned_families(), do: refute(css =~ family)
      assert length(String.split(css, "@font-face")) == 2
    end

    test "missing_pin_sources/1 names only the sources that are absent" do
      fonts = fonts!([entry("Traulha Regulara"), entry("Boogy Brut Regular")])

      assert FontBundle.missing_pin_sources(fonts) == ["Brut Grotesque Medium"]
    end
  end

  describe "report/2" do
    test "frequencies most frequent first, ties by tag, and tags outside the panel" do
      fonts =
        fonts!([
          entry("A", %{"features" => ["liga", "kern", "ss01"]}),
          entry("B", %{"features" => ["liga", "ss01"]}),
          entry("C", %{"features" => ["liga", "aalt"]})
        ])

      report = FontBundle.report(fonts, ["liga", "ss01"])

      assert report.fonts == 3
      assert report.frequencies == [{"liga", 3}, {"ss01", 2}, {"aalt", 1}, {"kern", 1}]
      assert report.unknown == ["aalt", "kern"]
    end
  end

  describe "compare_names/2" do
    test "reports both directions and ignores blank lines" do
      fonts = fonts!([entry("A"), entry("B")])

      assert FontBundle.compare_names(fonts, ["A", "", "Z"]) == %{
               burnt_without_font: ["Z"],
               fonts_without_tag: ["B"]
             }
    end

    test "a trailing space is a different string — the near-miss it exists to catch" do
      fonts = fonts!([entry("A")])

      assert %{burnt_without_font: ["A "], fonts_without_tag: ["A"]} =
               FontBundle.compare_names(fonts, ["A "])
    end
  end
end
