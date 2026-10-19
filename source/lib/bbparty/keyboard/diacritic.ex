defmodule Bbparty.Keyboard.Diacritic do
  @combining %{
    "´" => "́",
    "`" => "̀",
    "ˆ" => "̂",
    "^" => "̂",
    "˜" => "̃",
    "~" => "̃",
    "¨" => "̈",
    "ˇ" => "̌",
    "˚" => "̊",
    "˘" => "̆",
    "˙" => "̇",
    "˝" => "̋",
    "¸" => "̧",
    "˛" => "̨",
    "¯" => "̄"
  }

  @bases %{
    "´" => "aceilnorsuwyzACEILNORSUWYZ",
    "`" => "aeiouwyAEIOUWY",
    "ˆ" => "aceghijosuwyACEGHIJOSUWY",
    "^" => "aceghijosuwyACEGHIJOSUWY",
    "˜" => "ainouAINOU",
    "~" => "ainouAINOU",
    "¨" => "aeiouwyAEIOUWY",
    "ˇ" => "cdelnrstzCDELNRSTZ",
    "˚" => "auAU",
    "˘" => "aegiouAEGIOU",
    "˙" => "cegzCEGIZ",
    "˝" => "ouOU",
    "¸" => "cgklnrstCGKLNRST",
    "˛" => "aeiuAEIU",
    "¯" => "aeiouAEIOU"
  }

  for mark <- Map.keys(@bases), not Map.has_key?(@combining, mark) do
    raise CompileError, description: "diacritic #{inspect(mark)} has bases but no combining mark"
  end

  @compositions (for {mark, bases} <- @bases,
                     base <- String.graphemes(bases),
                     into: %{} do
                   composed =
                     :unicode.characters_to_nfc_binary(base <> Map.fetch!(@combining, mark))

                   case String.length(composed) do
                     1 ->
                       {{mark, base}, composed}

                     _ ->
                       raise CompileError,
                         description:
                           "#{inspect(mark)} + #{inspect(base)} does not compose to one " <>
                             "character (#{inspect(composed)}); it cannot be a base"
                   end
                 end)

  @marks @bases |> Map.keys() |> Enum.sort()

  @spec marks() :: [String.t()]
  def marks, do: @marks

  @spec mark?(term()) :: boolean()
  def mark?(char) when is_binary(char), do: Map.has_key?(@bases, char)
  def mark?(_char), do: false

  @spec bases(String.t()) :: [String.t()]
  def bases(mark) when is_binary(mark),
    do: @bases |> Map.get(mark, "") |> String.graphemes()

  def bases(_mark), do: []

  @spec compose(term(), term()) :: {:ok, String.t()} | :error
  def compose(mark, base) when is_binary(mark) and is_binary(base) do
    case Map.fetch(@compositions, {mark, base}) do
      {:ok, composed} -> {:ok, composed}
      :error -> :error
    end
  end

  def compose(_mark, _base), do: :error
end
