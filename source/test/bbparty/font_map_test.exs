defmodule Bbparty.FontMapTest do
  use ExUnit.Case, async: true

  alias Bbparty.FontMap

  describe "the manifest" do
    test "every font has a family and a feature list" do
      for {id, font} <- FontMap.fonts() do
        assert is_binary(id)
        assert is_binary(font.family), "#{id} has no family"
        assert is_list(font.features), "#{id} has no feature list"
      end
    end

    test "ids/0 is the sorted key set" do
      assert FontMap.ids() == FontMap.fonts() |> Map.keys() |> Enum.sort()
    end

    test "the hand-kept system faces are present" do
      assert "Arial" in FontMap.ids()
      assert "Chalkboard" in FontMap.ids()
      assert "Papyrus" in FontMap.ids()
    end

    test "every font's features are panel features, in panel order" do
      for {id, font} <- FontMap.fonts() do
        assert font.features == Enum.filter(FontMap.all_features(), &(&1 in font.features)),
               "#{id} has features outside the panel, or out of order: #{inspect(font.features)}"
      end
    end

    test "every id fits on an NFC tag" do
      for id <- FontMap.ids() do
        assert byte_size(id) <= Bbparty.FontBundle.max_id_bytes(),
               "#{inspect(id)} does not fit on a tag"
      end
    end
  end

  describe "all_features/0" do
    test "names each tag once" do
      assert FontMap.all_features() == Enum.uniq(FontMap.all_features())
    end

    test "small capitals is smcp, the tag fonts actually declare" do
      assert "smcp" in FontMap.all_features()
      refute "smsc" in FontMap.all_features()
    end

    test "every entry expands to four-character OpenType tags" do
      for switch <- FontMap.all_features(),
          tag <- FontMap.tags_for_switch(switch),
          do: assert(tag =~ ~r/\A[a-z0-9]{4}\z/, "#{switch} yields #{inspect(tag)}")
    end

    test "the panel carries the one composite switch" do
      assert "smcp+c2sc" in FontMap.all_features()
      assert FontMap.tags_for_switch("smcp+c2sc") == ["smcp", "c2sc"]
    end
  end

  describe "feature_tags/0" do
    test "is all_features/0 expanded and deduplicated, in panel order" do
      expected =
        FontMap.all_features() |> Enum.flat_map(&FontMap.tags_for_switch/1) |> Enum.uniq()

      assert FontMap.feature_tags() == expected
    end

    test "the composite switch's second tag is there, and only once" do
      assert "c2sc" in FontMap.feature_tags()
      assert Enum.count(FontMap.feature_tags(), &(&1 == "smcp")) == 1
    end
  end

  describe "latching?/1" do
    test "the stylistic sets are pushbuttons" do
      for n <- 1..20 do
        refute FontMap.latching?("ss" <> String.pad_leading("#{n}", 2, "0"))
      end
    end

    test "every other panel switch is a lever, the composite included" do
      levers = Enum.reject(FontMap.all_features(), &String.starts_with?(&1, "ss"))

      assert "smcp+c2sc" in levers
      assert Enum.all?(levers, &FontMap.latching?/1)
    end

    test "only a two-digit set counts" do
      assert FontMap.latching?("ss1")
      assert FontMap.latching?("ss001")
      assert FontMap.latching?("ssab")
    end
  end

  describe "tags_for_switch/1" do
    test "a plain switch carries one tag" do
      assert FontMap.tags_for_switch("liga") == ["liga"]
    end

    test "is total on anything a mis-commissioned switch could hold" do
      assert FontMap.tags_for_switch(nil) == []
      assert FontMap.tags_for_switch(42) == []
      assert FontMap.tags_for_switch("") == []
      assert FontMap.tags_for_switch("+") == []
    end
  end

  describe "feature_settings/1" do
    defp settings(active), do: FontMap.feature_settings(active)

    test "states every panel tag, so both positions of a switch mean something" do
      value = settings([])

      for tag <- FontMap.feature_tags() do
        assert value =~ ~s("#{tag}" 0), "#{tag} is not stated"
      end
    end

    test "ligatures are off unless a switch says otherwise" do
      assert settings([]) =~ ~s("liga" 0)
      assert settings(["liga"]) =~ ~s("liga" 1)
    end

    test "the composite switch turns both of its tags on together" do
      value = settings(["smcp+c2sc"])

      assert value =~ ~s("smcp" 1)
      assert value =~ ~s("c2sc" 1)
    end

    test "the plain small-caps switch leaves c2sc alone" do
      value = settings(["smcp"])

      assert value =~ ~s("smcp" 1)
      assert value =~ ~s("c2sc" 0)
    end

    test "anything outside the panel contributes nothing" do
      assert settings(["kern", :free_text, nil, "not a tag"]) == settings([])
    end

    test "is a well-formed font-feature-settings value" do
      assert settings(["liga", "ss01"]) =~ ~r/\A"[a-z0-9]{4}" [01](, "[a-z0-9]{4}" [01])*\z/
    end
  end

  describe "lookups are total" do
    test "an unknown font has no features and no family" do
      assert FontMap.features_for_font("no-such-font") == []
      assert FontMap.family_for_font("no-such-font") == nil
      refute FontMap.known?("no-such-font")
    end

    test "no font at all is the same as an unknown one" do
      assert FontMap.features_for_font(nil) == []
      assert FontMap.family_for_font(nil) == nil
      refute FontMap.known?(nil)
    end

    test "a payload that is not even a string" do
      refute FontMap.known?(42)
      assert FontMap.features_for_font(42) == []
    end
  end

  describe "a known font" do
    test "resolves its features and its family" do
      assert FontMap.known?("Arial")
      assert FontMap.family_for_font("Arial") == "Arial"
      assert "liga" in FontMap.features_for_font("Arial")
    end

    test "a composite switch needs both its tags to count as offered" do
      refute "c2sc" in FontMap.features_for_font("Arial")
      refute "smcp+c2sc" in FontMap.features_for_font("Arial")

      both =
        Enum.find(FontMap.ids(), fn id ->
          offered = FontMap.features_for_font(id)
          "smcp" in offered and "smcp+c2sc" in offered
        end)

      assert both, "no font in the manifest carries both smcp and c2sc"
    end

    test "family defaults to the id when the manifest omits it" do
      assert FontMap.family_for_font("Papyrus") == "Papyrus"
    end
  end
end
