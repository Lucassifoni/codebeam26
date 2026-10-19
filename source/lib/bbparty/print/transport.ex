defmodule Bbparty.Print.Transport do
  @callback send(iodata(), keyword()) :: :ok | {:error, term()}

  @default_timeout 15_000

  @spec run(String.t(), [String.t()], keyword()) :: {:ok, String.t()} | {:error, term()}
  def run(command, args, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    env = Keyword.get(opts, :env, [])

    task =
      Task.async(fn ->
        try do
          {:ran, System.cmd(command, args, env: env, stderr_to_stdout: true)}
        rescue
          ErlangError -> :not_found
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ran, {output, 0}}} -> {:ok, output}
      {:ok, {:ran, {output, status}}} -> {:error, {:command_failed, status, String.trim(output)}}
      {:ok, :not_found} -> {:error, {:command_not_found, command}}
      {:exit, reason} -> {:error, {:command_crashed, reason}}
      nil -> {:error, {:command_timed_out, command, timeout}}
    end
  end

  @spec send(iodata(), keyword()) :: :ok | {:error, term()}
  def send(payload, opts \\ []) do
    {module, configured} = configured()
    module.send(payload, Keyword.merge(configured, opts))
  end

  @spec configured() :: {module(), keyword()}
  def configured do
    case Application.get_env(:bbparty, :print_transport) do
      nil -> {platform_default(), []}
      opts when is_list(opts) -> {platform_default(), opts}
      module when is_atom(module) -> {module, []}
      {module, opts} -> {module, opts}
    end
  end

  @spec platform_default() :: module()
  def platform_default, do: platform_default(:os.type())

  def platform_default({:unix, :darwin}), do: Bbparty.Print.Transport.MacUsb
  def platform_default({:unix, :linux}), do: Bbparty.Print.Transport.Device
  def platform_default(_other), do: Bbparty.Print.Transport.Device
end
