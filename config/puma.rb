threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
threads threads_count, threads_count

# Bind to loopback only — nginx (fronted by the Cloudflare Tunnel) is the
# sole entry point, so Puma must not be reachable directly on the LAN.
bind "tcp://#{ENV.fetch("BIND_HOST") { "127.0.0.1" }}:#{ENV.fetch("PORT") { 3000 }}"
environment ENV.fetch("RAILS_ENV") { "development" }
pidfile ENV.fetch("PIDFILE") { "tmp/pids/server.pid" }

workers ENV.fetch("WEB_CONCURRENCY") { 0 }
plugin :tmp_restart
