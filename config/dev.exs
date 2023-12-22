import Config

config :redis_mutex, redis_url: "redis://localhost:6379"

config :redis_mutex, RedisMutex,
  otp_app: :redis_mutex,
  lock_module: RedisMutex.LockMock,
  redis_url: "redis://localhost:6379"
