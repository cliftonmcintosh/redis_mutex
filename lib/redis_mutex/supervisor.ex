defmodule RedisMutex.Supervisor do
  @moduledoc """
  The supervisor module for RedisMutex.
  """
  use Supervisor

  alias RedisMutex.ConfigParser

  require Logger

  @type start_options :: [
          name: module(),
          otp_app: atom(),
          lock_module: module(),
          redis_url: String.t(),
          redix_config: RedisMutex.connection_options()
        ]

  @spec start_link(atom(), module(), module(), [start_options()]) :: Supervisor.on_start()
  def start_link(otp_app, module, lock_module, opts)
      when is_atom(otp_app) and is_atom(lock_module) and
             is_list(opts) do
    Logger.info("#{__MODULE__} start_link otp_app: #{inspect(otp_app)}")
    Logger.info("#{__MODULE__} start_link module: #{inspect(module)}")
    Logger.info("#{__MODULE__} start_link lock_module: #{inspect(lock_module)}")
    Logger.info("#{__MODULE__} start_link opts: #{inspect(opts)}")
    Supervisor.start_link(__MODULE__, {otp_app, module, lock_module, opts}, name: __MODULE__)
  end

  @impl Supervisor
  @spec init({atom(), module(), module(), start_options()}) ::
          {:ok, {Supervisor.sup_flags(), [Supervisor.child_spec()]}}
  def init({otp_app, module, lock_module, opts}) do
    parsed_opts = ConfigParser.parse(otp_app, module, opts)

    Logger.info("#{__MODULE__} init otp_app: #{inspect(otp_app)}")
    Logger.info("#{__MODULE__} init module: #{inspect(module)}")
    Logger.info("#{__MODULE__} init lock_module: #{inspect(lock_module)}")
    Logger.info("#{__MODULE__} init opts: #{inspect(opts)}")
    Logger.info("#{__MODULE__} init parsed_opts: #{inspect(parsed_opts)}")

    children = [
      {lock_module, [parsed_opts]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
