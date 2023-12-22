defmodule RedisMutexTest do
  use ExUnit.Case, async: true

  import Mox

  alias RedisMutex.LockMock

  setup :verify_on_exit!

  defmodule MyRedisMutex do
    use RedisMutex, otp_app: :redis_mutex, lock_module: RedisMutex.LockMock
  end

  defmodule RedisMutexUser do
    require RedisMutexTest.MyRedisMutex

    def one_plus_one(key) do
      MyRedisMutex.with_lock key do
        1 + 1
      end
    end

    def one_plus_two(key, timeout) do
      MyRedisMutex.with_lock key, timeout do
        1 + 2
      end
    end

    def two_plus_two(key, timeout, expiry) do
      MyRedisMutex.with_lock key, timeout, expiry do
        2 + 2
      end
    end
  end

  setup do
    stub(LockMock, :child_spec, fn _opts -> :ignore end)
    stub(LockMock, :start_link, fn _opts -> :ignore end)
    start_supervised(MyRedisMutex, [])
    :ok
  end

  describe "__using__/1" do
    test "should use the lock module specified" do
      my_key = "my-key"
      my_timeout = 200
      my_expiry = 2_000

      expect(LockMock, :with_lock, fn key, timeout, expiry, do_clause ->
        assert key == my_key
        assert timeout == my_timeout
        assert expiry == my_expiry

        [do: block_value] =
          quote do
            unquote(do_clause)
          end

        block_value
      end)

      assert 4 == RedisMutexUser.two_plus_two(my_key, my_timeout, my_expiry)
    end

    test "should handle two arguments" do
      my_key = "my-key"

      expect(LockMock, :with_lock, fn key, _timeout, _expiry, do_clause ->
        assert key == my_key

        [do: block_value] =
          quote do
            unquote(do_clause)
          end

        block_value
      end)

      assert 2 == RedisMutexUser.one_plus_one(my_key)
    end

    test "should handle three arguments" do
      my_key = "my-key"
      my_timeout = 200

      expect(LockMock, :with_lock, fn key, timeout, _expiry, do_clause ->
        assert key == my_key
        assert timeout == my_timeout

        [do: block_value] =
          quote do
            unquote(do_clause)
          end

        block_value
      end)

      assert 3 == RedisMutexUser.one_plus_two(my_key, my_timeout)
    end
  end
end
