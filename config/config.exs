# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

envar = fn name ->
  case List.keyfind(Application.loaded_applications(), :distillery, 0) do
    nil -> System.get_env(name)
    _ -> "${#{name}}"
  end
end

config :logger,
  :console,
  metadata: [:request_id, :pid, :module],
  level: :debug

config :mroxy, Mroxy.ProxyListener,
  host: envar.("MROXY_PROXY_HOST") || "localhost",
  port: envar.("MROXY_PROXY_PORT") || "1334"

config :mroxy, Mroxy.ProxyServer,
  packet_trace: false,
  downstream_host: envar.("DOWNSTREAM_HOST") || "localhost",
  downstream_port: envar.("DOWNSTREAM_PORT") || "1443",
  downstream_logger_host: envar.("DOWNSTREAM_LOGGER_HOST") || "localhost",
  downstream_logger_port: envar.("DOWNSTREAM_LOGGER_PORT") || "5000"

