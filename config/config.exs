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
       port: envar.("MROXY_PORT") || "1334"

config :mroxy, Mroxy.ProxyServer,
       packet_trace: false,
       ds_host: envar.("DS_HOST") || "localhost",
       ds_port: envar.("DS_PORT") || "1433",
       logger_host: envar.("LOGGER_HOST") || "localhost",
       logger_port: envar.("LOGGER_PORT") || "8000"

