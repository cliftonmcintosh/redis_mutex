defmodule RedisMutex do
  @moduledoc """
  An Elixir library for using Redis locks.
  """

  @type socket_options :: [
          customize_hostname_check: [
            match_fun: function()
          ]
        ]

  @type connection_options :: [
          host: String.t(),
          port: non_neg_integer(),
          ssl: boolean(),
          socket_opts: socket_options()
        ]

  @type start_options :: {:redis_url, String.t()} | {:redix_config, connection_options()}

  @type using_options :: {:otp_app, atom()}

  @default_lock_module RedisMutex.Lock
  @default_timeout :timer.seconds(40)
  @default_expiry :timer.seconds(20)

  @spec __using__([using_options()]) :: term()
  defmacro __using__(opts) do
    require Logger
    Logger.info("#{__MODULE__} module name")
    Logger.info("#{__MODULE__} __using__ opts: #{inspect(opts)}")
    {otp_app, otp_app_opts} = Keyword.pop(opts, :otp_app)
    config_opts = Application.get_env(otp_app, __MODULE__)
    start_opts = Keyword.merge(config_opts, otp_app_opts)
    Logger.info("#{__MODULE__} __using__ config_opts: #{inspect(config_opts)}")
    Logger.info("#{__MODULE__} __using__ otp_app_opts: #{inspect(otp_app_opts)}")
    Logger.info("#{__MODULE__} __using__ start_opts: #{inspect(start_opts)}")

    Logger.info(
      "Application.get_env(otp_app, __MODULE__): #{inspect(Application.get_env(otp_app, __MODULE__))}"
    )

    Logger.info(
      "Application.get_env(otp_app, __MODULE__)[:lock_module]: #{inspect(Application.get_env(otp_app, __MODULE__)[:lock_module])}"
    )

    lock_module =
      otp_app_opts[:lock_module] ||
        Application.get_env(otp_app, __MODULE__)[:lock_module] ||
        @default_lock_module

    quote do
#      require unquote(lock_module)

      @lock_module unquote(lock_module)
      @default_timeout :timer.seconds(40)
      @default_expiry :timer.seconds(20)

      def child_spec(opts \\ []) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]},
          type: :supervisor
        }
      end

      @spec start_link([RedisMutex.start_options()]) :: Supervisor.on_start()
      def start_link(opts \\ []) do
        app = unquote(otp_app)
        Logger.info("#{__MODULE__} start_link app #{inspect(app)}")

        Logger.info("RedisMutex, module: #{__MODULE__}, start_link opts #{inspect(opts)}")

        supervisor_opts = Keyword.merge(unquote(start_opts), opts)

        RedisMutex.Supervisor.start_link(
          app,
          __MODULE__,
          @lock_module,
          supervisor_opts ++ [name: RedisMutex]
        )
      end

      def with_lock(key, timeout \\ @default_timeout, expiry \\ @default_expiry, fun) do
        @lock_module.with_lock(key, timeout, expiry, fun)
      end
    end
  end
end
