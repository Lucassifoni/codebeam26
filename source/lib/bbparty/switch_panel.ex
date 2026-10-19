defmodule Bbparty.SwitchPanel do
  @drives 8
  @senses 8

  @wired_drives 5
  @wired_senses 6

  @pitch 120

  @spec drives() :: pos_integer()
  def drives, do: @drives

  @spec senses() :: pos_integer()
  def senses, do: @senses

  @spec wired_crosspoints() :: [{non_neg_integer(), non_neg_integer()}]
  def wired_crosspoints do
    for drive <- 0..(@wired_drives - 1), sense <- 0..(@wired_senses - 1), do: {drive, sense}
  end

  @spec valid_address?(term(), term()) :: boolean()
  def valid_address?(drive, sense) when is_integer(drive) and is_integer(sense) do
    drive >= 0 and drive < @drives and sense >= 0 and sense < @senses
  end

  def valid_address?(_drive, _sense), do: false

  @spec switch_id(non_neg_integer(), non_neg_integer()) :: String.t()
  def switch_id(drive, sense), do: "switch_#{drive}_#{sense}"

  @spec address(String.t() | atom()) :: {:ok, {non_neg_integer(), non_neg_integer()}} | :error
  def address(id) when is_atom(id), do: address(Atom.to_string(id))

  def address("switch_" <> rest) do
    with [drive, sense] <- String.split(rest, "_"),
         {drive, ""} <- Integer.parse(drive),
         {sense, ""} <- Integer.parse(sense),
         true <- valid_address?(drive, sense) do
      {:ok, {drive, sense}}
    else
      _ -> :error
    end
  end

  def address(_id), do: :error

  @spec pitch() :: pos_integer()
  def pitch, do: @pitch

  @spec default_position(non_neg_integer(), non_neg_integer()) :: %{String.t() => integer()}
  def default_position(drive, sense), do: position(drive, sense, @pitch, {0, 0})

  @spec grid_plan([String.t() | atom()], keyword()) ::
          [{String.t() | atom(), %{String.t() => integer()}}]
  def grid_plan(ids, opts \\ []) do
    pitch = Keyword.get(opts, :pitch, @pitch)
    origin = Keyword.get(opts, :origin, {0, 0})

    Enum.flat_map(ids, fn id ->
      case address(id) do
        {:ok, {drive, sense}} -> [{id, position(drive, sense, pitch, origin)}]
        :error -> []
      end
    end)
  end

  defp position(drive, sense, pitch, {x, y}),
    do: %{"x" => x + sense * pitch, "y" => y + drive * pitch}

  @spec pressed?(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: boolean()
  def pressed?(bits, drive, sense) when is_integer(bits) do
    import Bitwise
    (bits >>> (drive * @senses + sense) &&& 1) == 1
  end

  @spec pressed(non_neg_integer()) :: [{non_neg_integer(), non_neg_integer()}]
  def pressed(bits) when is_integer(bits) do
    for drive <- 0..(@drives - 1),
        sense <- 0..(@senses - 1),
        pressed?(bits, drive, sense),
        do: {drive, sense}
  end

  @spec describe_address(term(), term()) :: String.t()
  def describe_address(drive, sense) do
    "crosspoint (#{inspect(drive)}, #{inspect(sense)}) is outside the #{@drives}×#{@senses} matrix"
  end
end
