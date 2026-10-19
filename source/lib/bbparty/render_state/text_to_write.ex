defmodule Bbparty.RenderState.TextToWrite do
  @source_text """
  Typography is the art and technique of arranging type to make written language legible, readable and appealing when displayed. The arrangement of type involves selecting typefaces, point sizes, line lengths, line-spacing, and letter-spacing, and adjusting the space between pairs of letters. The term typography is also applied to the style, arrangement, and appearance of the letters, numbers, and symbols created by the process. Type design is a closely related craft, sometimes considered part of typography; most typographers do not design typefaces, and some type designers do not consider themselves typographers. Typography also may be used as an ornamental and decorative device, unrelated to the communication of information. Typography is the work of typesetters, compositors, typographers, graphic designers, art directors, manga artists, comic book artists, and now—anyone who arranges words, letters, numbers, and symbols for publication, display, or distribution, from clerical workers and newsletter writers to anyone self-publishing materials. Until the Digital Age, typography was a specialized occupation. Digitization opened up typography to new generations of previously unrelated designers and lay users. As the capability to create typography has become ubiquitous, the application of principles and best practices developed over generations of skilled workers and professionals has diminished. So at a time when scientific techniques. The fundamental character of a typeface is determined by the basic shape of the letters. This includes characteristics such as the height and width of the letters, the thickness of the strokes, and the spacing between letters. These characteristics work together to create the overall personality of the typeface, which can range from elegant and sophisticated to bold and playful. The choice of typeface can greatly influence how text is perceived and understood by readers. In modern digital typography, designers have access to thousands of typefaces, each with its own unique characteristics and intended uses. Some typefaces are designed for body text and are optimized for readability at small sizes, while others are created for display purposes and work best at larger sizes. The selection of the right typeface for a particular project requires careful consideration of factors such as the intended audience, the medium of publication, and the overall design aesthetic. Letter spacing, also known as tracking, refers to the uniform adjustment of space between all letters in a piece of text. Proper letter spacing is crucial for readability and can dramatically affect how text appears on a page. Too little space can make text appear cramped and difficult to read, while too much space can make it seem loose and disconnected. The optimal letter spacing varies depending on the typeface, size, and intended use of the text. Line spacing, or leading, is another fundamental aspect of typography that affects readability. It refers to the vertical space between lines of text. Appropriate leading helps guide the reader's eye from one line to the next and prevents lines from appearing too crowded or too sparse. Like letter spacing, the optimal line spacing depends on various factors including typeface design, text size, and line length. Color in typography doesn't just refer to the literal color of the text, but also to the overall darkness or lightness of a block of text when viewed from a distance. This typographic color is affected by factors such as the weight of the typeface, letter spacing, line spacing, and the amount of text on a page. Achieving good typographic color creates a harmonious and readable text block that is pleasant to the eye. The hierarchy of information is established through the strategic use of different type sizes, weights, and styles. This helps readers navigate through content efficiently by clearly indicating what information is most important. Headlines, subheadings, body text, captions, and other text elements should be visually distinct from one another while maintaining an overall sense of unity and coherence throughout the design. Kerning is the adjustment of space between specific pairs of letters to improve the overall appearance and readability of text. Unlike tracking, which affects all letters uniformly, kerning addresses the optical spacing between individual letter combinations. Some letter pairs, such as "AV" or "To," naturally create awkward gaps when set with standard spacing, and kerning helps to visually balance these combinations. The grid system in typography provides a framework for organizing text and other design elements on a page. A well-constructed grid helps create consistency and hierarchy while providing flexibility for creative expression. Grids can be simple or complex, with columns, rows, and margins that guide the placement of text blocks, images, and other visual elements.
  """

  @words @source_text |> String.split(~r/\s+/, trim: true)
  @text Enum.join(@words, " ")
  @roll_words @source_text
              |> String.split(~r/[^\p{L}']+/u, trim: true)
              |> Enum.reject(&String.contains?(&1, "'"))
              |> Enum.map(&String.downcase/1)
              |> Enum.uniq()
  @count String.length(@text)

  @spec text() :: String.t()
  def text, do: @text

  @spec words() :: [String.t()]
  def words, do: @words

  @spec roll_words() :: [String.t()]
  def roll_words, do: @roll_words

  @spec count() :: pos_integer()
  def count, do: @count

  @spec take(integer()) :: String.t()
  def take(n) when is_integer(n) and n <= 0, do: ""
  def take(n) when is_integer(n), do: String.slice(@text, 0, n)
end
