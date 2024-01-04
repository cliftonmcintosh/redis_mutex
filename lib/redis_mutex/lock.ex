if Code.ensure_loaded?(Redix) do
  defmodule RedisMutex.Lock do
    @moduledoc """
    Defines the lock behaviour for RedisMutex.
    """

    @default_timeout :timer.seconds(40)
    @default_expiry :timer.seconds(20)
    @unlock_script """
    if redis.call("get", KEYS[1]) == ARGV[1] then
      return redis.call("del", KEYS[1])
    else
      return 0
    end
    """

    @type start_options :: String.t() | Keyword.t()

    @callback child_spec(opts :: Keyword.t()) :: Supervisor.child_spec()

    @callback start_link(start_options :: start_options()) :: {:ok, pid()} | {:error, any()}

    @callback with_lock(
                key :: String.t(),
                timeout :: integer(),
                expiry :: integer(),
                fun :: (-> any())
              ) :: any()

    @spec child_spec(Keyword.t()) :: Supervisor.child_spec()
    def child_spec(opts) do
      %{
        id: __MODULE__,
        start: {__MODULE__, :start_link, opts},
        type: :worker,
        restart: :permanent,
        shutdown: 500
      }
    end

    @spec start_link(start_options()) :: :ignore | {:error, any} | {:ok, pid}
    def start_link(start_options \\ []) do
      {redis_url, redix_opts} = Keyword.pop(start_options, :redis_url)
      {name, redix_opts} = Keyword.pop(redix_opts, :name)

      case redis_url do
        nil ->
          [name: name, sync_connect: true]
          |> Keyword.merge(redix_opts)
          |> Redix.start_link()

        redis_url when is_binary(redis_url) ->
          Redix.start_link(redis_url, name: name, sync_connect: true)
      end
    end

    @spec with_lock(key :: String.t(), timeout :: integer(), expiry :: integer(), fun :: (() -> any())) :: any()
    def with_lock(key, timeout, expiry, fun) do
      uuid = Uniq.UUID.uuid1()
      RedisMutex.Lock.take_lock(key, uuid, timeout, expiry)
      result = fun.()
      RedisMutex.Lock.unlock(key, uuid)
      result
    end

    @doc """
    This function takes in a key, unique string, and a timeout in milliseconds.
    It will call itself recursively until it is able to set a lock
    or the timeout expires.
    """
    def take_lock(
          key,
          uuid,
          timeout \\ @default_timeout,
          expiry \\ @default_expiry,
          finish \\ nil
        )

    def take_lock(key, uuid, timeout, expiry, nil) do
      finish = DateTime.add(DateTime.utc_now(), timeout, :millisecond)
      take_lock(key, uuid, timeout, expiry, finish)
    end

    def take_lock(key, uuid, timeout, expiry, finish) do
      if DateTime.compare(finish, DateTime.utc_now()) == :lt do
        raise RedisMutex.Error, message: "Unable to obtain lock."
      end

      if !lock(key, uuid, expiry) do
        take_lock(key, uuid, timeout, expiry, finish)
      end
    end

    @doc """
    This function takes in a key and a unique identifier to set it in Redis.
    This is how a lock is identified in Redis. If a key/value pair is able to be
    set in Redis, `lock` returns `true`. If it isn't able to set in Redis, `lock`
    returns `false`.
    """
    def lock(key, value, expiry) do
      case Redix.command!(client(), ["SET", key, value, "NX", "PX", "#{expiry}"]) do
        "OK" -> true
        nil -> false
      end
    end

    @doc """
    This function takes in the key/value pair that are to be released in Redis
    """
    def unlock(key, value) do
      case Redix.command!(client(), ["EVAL", @unlock_script, 1, key, value]) do
        1 -> true
        0 -> false
      end
    end

    defp client, do: Process.whereis(RedisMutex)
  end
end
