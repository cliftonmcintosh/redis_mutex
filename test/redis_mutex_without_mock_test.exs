defmodule RedisMutexWithoutMockTest do
  use ExUnit.Case, async: false

  @moduletag :redis_dependent

  defmodule MyRedisMutex do
    use RedisMutex, otp_app: :redis_mutex, lock_module: RedisMutex.Lock
  end

  defmodule RedisMutexUser do
    require RedisMutexWithoutMockTest.MyRedisMutex

    def two_threads_lock do
      MyRedisMutex.with_lock "two_threads_lock" do
        start_time = DateTime.utc_now()
        end_time = DateTime.utc_now()
        {start_time, end_time}
      end
    end

    def two_threads_one_loses_lock do
      try do
        MyRedisMutex.with_lock "two_threads_one_loses_lock", 100 do
          start_time = DateTime.utc_now()
          :timer.sleep(1000)
          end_time = DateTime.utc_now()
          {start_time, end_time}
        end
      rescue
        RedisMutex.Error -> :timed_out
      end
    end

    def long_running_task do
      MyRedisMutex.with_lock "two_threads_lock_expires", 10_000, 250 do
        :timer.sleep(10_000)
      end
    end

    def quick_task do
      MyRedisMutex.with_lock "two_threads_lock_expires", 1000, 500 do
        "I RAN!!!"
      end
    end
  end

  describe "with_lock/4" do
    setup do
      start_supervised(MyRedisMutex, [])
      :ok
    end

    test "works with two tasks contending for the same lock, making one run after the other" do
      res =
        run_in_parallel(2, 5000, fn ->
          RedisMutexUser.two_threads_lock()
        end)

      [start_1, end_1, start_2, end_2] =
        Enum.flat_map(res, fn result ->
          case result do
            {:ok, {start_time, end_time}} -> [start_time, end_time]
            {:error, e} -> raise e
          end
        end)

      assert DateTime.compare(start_1, end_1) == :lt
      assert DateTime.compare(start_2, end_2) == :lt

      # one ran before the other, regardless of which
      assert (DateTime.compare(start_1, start_2) == :lt and DateTime.compare(end_1, end_2) == :lt) or
               (DateTime.compare(start_2, start_1) == :lt and
                  DateTime.compare(end_2, end_1) == :lt)
    end

    test "only runs one of the two tasks when the other times out attempting to acquire the lock" do
      res =
        run_in_parallel(2, 5000, fn ->
          RedisMutexUser.two_threads_one_loses_lock()
        end)

      [result_1, result_2] =
        Enum.map(res, fn result ->
          IO.puts("result: #{inspect(result)}")
          case result do
            {:ok, {start_time, end_time}} -> [start_time, end_time]
            error -> error
          end
        end)

      # make sure one task failed and one task succeeded, regardless of which
      cond do
        is_tuple(result_1) ->
          assert {:ok, :timed_out} == result_1
          [start_time, end_time] = result_2
          assert DateTime.compare(start_time, end_time) == :lt

        is_tuple(result_2) ->
          assert {:ok, :timed_out} == result_2
          [start_time, end_time] = result_1
          assert DateTime.compare(start_time, end_time) == :lt

        true ->
          flunk("Both tasks ran, which means our lock timeout did not work!")
      end
    end

    test "expires the lock after the given time" do
      # Kick off a task that will run for a long time, holding the lock
      t =
        Task.async(fn ->
          RedisMutexUser.long_running_task()
        end)

      # let enough time pass so that the lock expire
      Task.yield(t, 1000)

      # try to run another task and see if it gets the lock
      results = RedisMutexUser.quick_task()

      Task.shutdown(t, :brutal_kill)

      assert results == "I RAN!!!"
    end
  end

  defp run_in_parallel(concurrency, timeout, content) do
    1..concurrency
    |> Enum.map(fn _ ->
      Task.async(content)
    end)
    |> Task.yield_many(timeout)
    |> Enum.map(fn {task, res} ->
      # Shut down the tasks that did not reply nor exit
      res || Task.shutdown(task, :brutal_kill)
    end)
  end
end
