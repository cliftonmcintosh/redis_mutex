import Config

config :redis_mutex, redis_url: "redis://localhost:6379"

config :redis_mutex, RedisMutex,
  lock_module: RedisMutex.LockMock,
  redis_url: "redis://localhost:6379"
