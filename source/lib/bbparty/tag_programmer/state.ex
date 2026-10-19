defmodule Bbparty.TagProgrammer.State do
  @enforce_keys [:items]
  defstruct items: [], cursor: 0, phase: :idle, last_read: nil, error: nil

  @type status :: :pending | :writing | :done | :failed | :skipped

  @type item :: %{
          index: non_neg_integer(),
          text: String.t(),
          status: status(),
          read: String.t() | nil
        }

  @type event ::
          {:tag_read, %{optional(any) => any, text: String.t()}}
          | {:write_result, %{optional(any) => any, ok: boolean()}}
          | {:tag_gone}
          | {:pong}
          | {:hello}

  @type effect :: {:write_tag, String.t()}

  @type t :: %__MODULE__{
          items: [item()],
          cursor: non_neg_integer(),
          phase: :idle | :awaiting_tag | :awaiting_removal | :failed | :complete,
          last_read: String.t() | nil,
          error: String.t() | nil
        }

  @spec new([String.t()]) :: t()
  def new(texts) when is_list(texts) do
    items =
      texts
      |> Enum.with_index()
      |> Enum.map(fn {text, index} ->
        %{index: index, text: text, status: :pending, read: nil}
      end)

    %__MODULE__{items: items, cursor: 0, phase: :idle}
  end

  @spec current(t()) :: item() | nil
  def current(%__MODULE__{items: items, cursor: cursor}), do: Enum.at(items, cursor)

  @spec start(t()) :: {t(), [effect()]}
  def start(%__MODULE__{} = state), do: program_current(%{state | cursor: 0, error: nil})

  @spec handle_event(t(), event()) :: {t(), [effect()]}
  def handle_event(%__MODULE__{phase: :awaiting_tag} = state, {:tag_read, %{text: text}}) do
    {%{state | last_read: text}, []}
  end

  def handle_event(%__MODULE__{phase: :awaiting_tag} = state, {:write_result, %{ok: ok}}) do
    expected = current(state).text

    cond do
      ok and state.last_read == expected ->
        {%{
           state
           | items: put_status(state, :done, state.last_read),
             phase: :awaiting_removal,
             error: nil
         }, []}

      ok ->
        fail(
          state,
          "read-back mismatch: wrote #{inspect(expected)}, read #{inspect(state.last_read)}"
        )

      true ->
        fail(state, "device reported the write failed")
    end
  end

  def handle_event(%__MODULE__{phase: :awaiting_removal} = state, {:tag_gone}) do
    advance(state)
  end

  def handle_event(%__MODULE__{} = state, _event), do: {state, []}

  @spec retry(t()) :: {t(), [effect()]}
  def retry(%__MODULE__{phase: :failed} = state), do: program_current(%{state | error: nil})
  def retry(%__MODULE__{} = state), do: {state, []}

  @spec skip(t()) :: {t(), [effect()]}
  def skip(%__MODULE__{phase: phase} = state)
      when phase in [:awaiting_tag, :awaiting_removal, :failed] do
    advance(%{state | items: put_status(state, :skipped, nil), error: nil})
  end

  def skip(%__MODULE__{} = state), do: {state, []}

  @spec summary(t()) :: %{
          done: non_neg_integer(),
          failed: non_neg_integer(),
          total: non_neg_integer()
        }
  def summary(%__MODULE__{items: items}) do
    %{
      total: length(items),
      done: Enum.count(items, &(&1.status == :done)),
      failed: Enum.count(items, &(&1.status == :failed))
    }
  end

  defp advance(%__MODULE__{cursor: cursor} = state) do
    program_current(%{state | cursor: cursor + 1, last_read: nil, error: nil})
  end

  defp program_current(%__MODULE__{items: items, cursor: cursor} = state) do
    case Enum.at(items, cursor) do
      nil ->
        {%{state | phase: :complete}, []}

      item ->
        {%{
           state
           | items: List.replace_at(items, cursor, %{item | status: :writing}),
             phase: :awaiting_tag,
             last_read: nil
         }, [{:write_tag, item.text}]}
    end
  end

  defp fail(state, message) do
    {%{
       state
       | items: put_status(state, :failed, state.last_read),
         phase: :failed,
         error: message
     }, []}
  end

  defp put_status(%__MODULE__{items: items, cursor: cursor}, status, read) do
    case Enum.at(items, cursor) do
      nil -> items
      item -> List.replace_at(items, cursor, %{item | status: status, read: read})
    end
  end
end
