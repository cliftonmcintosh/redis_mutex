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

  @spec __using__([using_options()]) :: term()
  defmacro __using__(opts) do
    {otp_app, otp_app_opts} = Keyword.pop(opts, :otp_app)

    lock_module =
      otp_app_opts[:lock_module] ||
        Application.get_env(otp_app, __MODULE__)[:lock_module] ||
        @default_lock_module

    quote do
      import RedisMutex, only: [with_lock: 2, with_lock: 3, with_lock: 4]
      require unquote(lock_module)

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

        RedisMutex.Supervisor.start_link(
          app,
          __MODULE__,
          @lock_module,
          opts ++ [name: RedisMutex]
        )
      end

    end
  end

  defmacro with_lock(key, timeout \\ @default_timeout, expiry \\ @default_expiry, do: clause) do
    quote do
      key = unquote(key)
      timeout = unquote(timeout)
      expiry = unquote(expiry)

      @lock_module.with_lock(key, timeout, expiry) do
        clause
      end
    end
  end
end
