defmodule Mroxy.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  def start(_type, _args) do
    # HACK to get exec running as root.
    # Application.put_env(:exec, :root, true)

    proxy_opts = Application.get_env(:mroxy, Mroxy.ProxyListener)

    children = [
      Mroxy.ProxyListener.child_spec(proxy_opts),
    ]

    elixir_version = System.version()
    otp_release = :erlang.system_info(:otp_release)
    Logger.info("Started application: Elixir `#{elixir_version}` on OTP `#{otp_release}`.")

    opts = [strategy: :one_for_one, name: Mroxy.Supervisor]
    l = Supervisor.start_link(children, opts)
    Mroxy.ProxyListener.accept(proxy_opts)
    l
  end
end
