defmodule Bbparty.RenderState.TextToWriteTest do
  use ExUnit.Case, async: true

  alias Bbparty.RenderState.TextToWrite

  describe "words/0" do
    test "the source is split on whitespace, with nothing empty" do
      words = TextToWrite.words()

      assert Enum.all?(words, fn word -> word != "" end)
      refute Enum.any?(words, fn word -> String.match?(word, ~r/\s/) end)
    end

    test "there is enough text for the knob to be worth turning" do
      assert length(TextToWrite.words()) > 100
    end
  end

  describe "roll_words/0" do
    test "every word is lowercase letters and nothing else" do
      assert Enum.all?(TextToWrite.roll_words(), &String.match?(&1, ~r/^\p{Ll}+$/u))
    end

    test "punctuation is cut away, not kept inside a word" do
      words = TextToWrite.roll_words()

      assert "typography" in words
      assert "spacing" in words
      refute "doesn" in words
      refute "t" in words
    end

    test "each word appears once, so every word is equally likely" do
      words = TextToWrite.roll_words()

      assert words == Enum.uniq(words)
    end

    test "there are enough words for a roll to feel random" do
      assert length(TextToWrite.roll_words()) > 100
    end
  end

  describe "text/0 and count/0" do
    test "the text is the words, single-spaced" do
      assert TextToWrite.text() == Enum.join(TextToWrite.words(), " ")
    end

    test "count is in graphemes, the unit the cursor and the renderer use" do
      assert TextToWrite.count() == length(String.graphemes(TextToWrite.text()))
    end
  end

  describe "take/1" do
    test "returns the first n characters" do
      assert TextToWrite.take(3) ==
               TextToWrite.text() |> String.graphemes() |> Enum.take(3) |> Enum.join()
    end

    test "grows by exactly one character per step" do
      for n <- [1, 7, 42, 500] do
        assert String.length(TextToWrite.take(n)) == n
        assert String.starts_with?(TextToWrite.take(n + 1), TextToWrite.take(n))
      end
    end

    test "a non-ASCII character is taken whole" do
      at = TextToWrite.text() |> String.graphemes() |> Enum.find_index(&(&1 == "—"))

      assert at, "the source was expected to carry an em dash"
      assert String.last(TextToWrite.take(at + 1)) == "—"
    end

    test "nothing at or below zero" do
      assert TextToWrite.take(0) == ""
      assert TextToWrite.take(-5) == ""
    end

    test "past the end is the whole text, not a crash" do
      assert TextToWrite.take(TextToWrite.count() * 2) == TextToWrite.text()
    end
  end
end
