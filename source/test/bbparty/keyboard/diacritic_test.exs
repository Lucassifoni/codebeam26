defmodule Bbparty.Keyboard.DiacriticTest do
  use ExUnit.Case, async: true

  alias Bbparty.Keyboard.Diacritic

  describe "the marks" do
    test "are the fifteen spacing glyphs the keycaps carry" do
      assert Diacritic.marks() == Enum.sort(~w(´ ` ˆ ^ ˜ ~ ¨ ˇ ˚ ˘ ˙ ˝ ¸ ˛ ¯))
    end

    test "mark?/1 is total over anything a key might carry" do
      for char <- ~w(´ ˇ ¯), do: assert(Diacritic.mark?(char))
      for char <- ["a", "1", "😀", "", "´´", nil, :acute, 42], do: refute(Diacritic.mark?(char))
    end

    test "the ascii circumflex and tilde behave as their modifier-letter twins" do
      assert Diacritic.compose("^", "e") == Diacritic.compose("ˆ", "e")
      assert Diacritic.compose("~", "n") == Diacritic.compose("˜", "n")
      assert Diacritic.bases("^") == Diacritic.bases("ˆ")
      assert Diacritic.bases("~") == Diacritic.bases("˜")
    end
  end

  describe "compose/2" do
    test "every pair in the table makes exactly one codepoint" do
      for mark <- Diacritic.marks(), base <- Diacritic.bases(mark) do
        assert {:ok, composed} = Diacritic.compose(mark, base)
        assert String.length(composed) == 1, "#{mark} + #{base} is not one grapheme"

        assert byte_size(composed) > byte_size(base),
               "#{mark} + #{base} produced the bare letter"
      end
    end

    test "the result is precomposed, never a letter plus a combining mark" do
      assert Diacritic.compose("´", "e") == {:ok, "é"}
      assert Diacritic.compose("´", "e") != {:ok, "é"}
      assert :unicode.characters_to_nfd_binary("é") != "é"
    end

    test "refuses the pairs Unicode composes but the fonts cannot draw" do
      for {mark, base} <- [
            {"ˇ", "g"},
            {"ˇ", "u"},
            {"˜", "e"},
            {"˙", "s"},
            {"´", "g"},
            {"¸", "e"},
            {"¯", "y"},
            {"`", "n"}
          ] do
        assert Diacritic.compose(mark, base) == :error,
               "#{mark} + #{base} has no glyph in the library and must not compose"

        refute base in Diacritic.bases(mark)
      end
    end

    test "dot above is not symmetric between the cases" do
      assert Diacritic.compose("˙", "I") == {:ok, "İ"}
      assert Diacritic.compose("˙", "i") == :error
      assert Diacritic.compose("˙", "Z") == {:ok, "Ż"}
      assert Diacritic.compose("˙", "z") == {:ok, "ż"}
    end

    test "case is carried through for the marks that take both" do
      assert Diacritic.compose("¨", "o") == {:ok, "ö"}
      assert Diacritic.compose("¨", "O") == {:ok, "Ö"}
      assert Diacritic.compose("ˇ", "s") == {:ok, "š"}
      assert Diacritic.compose("ˇ", "S") == {:ok, "Š"}
    end

    test "is total: anything that is not a letter this mark takes is :error" do
      for base <- ["1", " ", "", "😀", "ab", "é", "´", nil, 42] do
        assert Diacritic.compose("´", base) == :error
      end

      for mark <- ["a", "", "¤", nil, 42] do
        assert Diacritic.compose(mark, "e") == :error
      end
    end
  end

  describe "bases/1" do
    test "lists the letters a mark takes, and nothing for anything else" do
      assert Diacritic.bases("˚") == ~w(a u A U)
      assert Diacritic.bases("˝") == ~w(o u O U)
      assert Diacritic.bases("x") == []
      assert Diacritic.bases(nil) == []
    end

    test "every base is a single ASCII letter" do
      for mark <- Diacritic.marks(), base <- Diacritic.bases(mark) do
        assert base =~ ~r/^[A-Za-z]$/, "#{inspect(base)} is not a plain letter"
      end
    end
  end
end
