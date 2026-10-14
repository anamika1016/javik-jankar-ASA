# This configuration file will be evaluated by Puma. The top-level methods that
# are invoked here are part of Puma's configuration DSL. For more information
# about methods provided by the DSL, see https://puma.io/puma/Puma/DSL.html.
#
# Puma starts a configurable number of processes (workers) and each process
# serves each request in a thread from an internal thread pool.
#
# You can control the number of workers using ENV["WEB_CONCURRENCY"]. You
# should only set this value when you want to run 2 or more workers. The
# default is already 1. You can set it to `auto` to automatically start a worker
# for each available processor.
#
# The ideal number of threads per worker depends both on how much time the
# application spends waiting for IO operations and on how much you wish to
# prioritize throughput over latency.
#
# As a rule of thumb, increasing the number of threads will increase how much
# traffic a given process can handle (throughput), but due to CRuby's
# Global VM Lock (GVL) it has diminishing returns and will degrade the
# response time (latency) of the application.
#
# The default is set to 3 threads as it's deemed a decent compromise between
# throughput and latency for the average Rails application.
#
# Any libraries that use a connection pool or another resource pool should
# be configured to provide at least as many connections as the number of
# threads. This includes Active Record's `pool` parameter in `database.yml`.
# The production host runs memory-heavy reports and forms alongside web
# requests. Two web threads keep interactive requests responsive without
# allowing three large JSON/report allocations to pressure Ruby GC and the
# primary database at the same time. An explicit environment value still wins.
threads_count = ENV.fetch("RAILS_MAX_THREADS", ENV.fetch("RAILS_ENV", "development") == "production" ? 2 : 3)
threads threads_count, threads_count

# This deployment is configured for a small-memory host.  Running two workers
# when WEB_CONCURRENCY is absent doubles the Ruby heap and allows six web
# threads to allocate concurrently, which causes long GC pauses across
# unrelated pages.  Production keeps the configured single-worker baseline;
# operators can still explicitly override it with WEB_CONCURRENCY.
worker_count = ENV.fetch("WEB_CONCURRENCY", ENV.fetch("RAILS_ENV", "development") == "production" ? 1 : 0)
if worker_count.to_s == "auto" || worker_count.to_i.positive?
  workers worker_count
  preload_app!
end

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
port ENV.fetch("PORT", 3000)

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

# Run the Solid Queue supervisor inside of Puma for single-server deployments.
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

# Specify the PID file. Defaults to tmp/pids/server.pid in development.
# In other environments, only set the PID file if requested.
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
