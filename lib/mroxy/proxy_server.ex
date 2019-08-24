defmodule Mroxy.ProxyServer do
  @moduledoc """
  Transparent Proxy Server manages the relay of communications between and
  upstream and downstream tcp connections.
  """
  use GenServer

  require Logger

  @downstream_tcp_opts [
    :binary,
    packet: 0,
    active: true,
    nodelay: true
  ]

  @logger_tcp_opts [
    :binary,
    packet: :raw,
    active: true,
    nodelay: true
  ]

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient,
      shutdown: 5000,
      type: :worker
    }
  end

  @doc """
  Spawns a process to manage connections between upstream and downstream
  connections.

  Keyword `args`:
  * `:upstream_socket` - `:gen_tcp` connection delegated from the `Mroxy.ProxyListener`
  """
  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @doc false
  def init(args) do
    upstream_socket = Keyword.get(args, :upstream_socket)
    popts = Application.get_env(:mroxy, Mroxy.ProxyServer, [])
    # check config for packet_trace
    packet_trace = popts |> Keyword.get(:packet_trace, false)
    # compose initial state
    {:ok,
      %{
        upstream: %{
          socket: upstream_socket
        },
        downstream: %{
          ds_host: Keyword.get(popts, :ds_host),
          ds_port: String.to_integer(Keyword.get(popts, :ds_port)),
          tcp_opts: @downstream_tcp_opts,
          socket: nil
        },
        logger: %{
          logger_host: Keyword.get(popts, :logger_host),
          logger_port: String.to_integer(Keyword.get(popts, :logger_port)),
          tcp_opts: @logger_tcp_opts,
          socket: nil
        },
        packet_trace: packet_trace
      }}
  end

  @doc false
  def handle_info(
        msg = {:tcp, upstream_socket, data},
        state = %{
          upstream: %{socket: upstream_socket},
          downstream: downstream = %{ds_host: ds_host, ds_port: ds_port, socket: nil},
          logger: logger = %{logger_host: logger_host, logger_port: logger_port, socket: nil}
        })
    do
    if state.packet_trace do
      Logger.debug("Up -> PROXY [rescheduled]: #{inspect(data)}")
    end
    # Establish the downstream TCP connection
    case :gen_tcp.connect(to_charlist(ds_host), ds_port, @downstream_tcp_opts) do
      {:ok, down_socket} -> Logger.debug("Downstream connection established")
                            # Add downstream connection information and socket to `ProxyServer` state
                            state = %{
                              state |
                              downstream: %{
                                downstream | socket: down_socket
                              }
                            }
                            state = case :gen_tcp.connect(to_charlist(logger_host), logger_port, @logger_tcp_opts) do
                              {:ok, logger_socket} ->
                                  Logger.debug("Logger connection established")
                                  # send the upstream ip for this connection to logger
                                  {:ok, {ip, _port}} = :inet.peername(logger_socket)
                                  :gen_tcp.send(logger_socket, String.pad_trailing(":::"<>to_string(:inet_parse.ntoa(ip)),100))
                                  :gen_tcp.send(logger_socket, "\n")
                                  %{
                                    state |
                                    logger: %{
                                      logger | socket: logger_socket
                                    }
                                  }
                              _ -> Logger.debug("Logger connection failed")
                                     state
                            end
                            send(self(), msg)
                            {:noreply, state}
      {:error, reason} -> Logger.error("Cannot connect downstream because #{reason}")
                          {:stop, :normal, state}
    end
  end

  def handle_info(
        {:tcp, upstream_socket, data},
        state = %{upstream: %{socket: upstream_socket}, downstream: %{socket: downstream_socket},
          logger: %{socket: nil} }
      ) do
    if state.packet_trace do
      Logger.debug("Up -> Down: #{inspect(data)}")
    end
    :gen_tcp.send(downstream_socket, data)
    {:noreply, state}
  end

  def handle_info(
        {:tcp, upstream_socket, data},
        state = %{upstream: %{socket: upstream_socket}, downstream: %{socket: downstream_socket},
          logger: %{socket: logger_socket} }
      ) do
    if state.packet_trace do
      Logger.debug("Up -> Down: #{inspect(data)}")
    end
    :gen_tcp.send(downstream_socket, data)
    :gen_tcp.send(logger_socket, ">>>"<>get_tstamp()<>"<<<"<>data)
    {:noreply, state}
  end

  def handle_info(
        {:tcp, downstream_socket, data},
        state = %{upstream: %{socket: upstream_socket}, downstream: %{socket: downstream_socket},
          logger: %{socket: nil} }
      ) do
    if state.packet_trace do
      Logger.debug("Up <- Down: #{inspect(data)}")
    end
    :gen_tcp.send(upstream_socket, data)
    {:noreply, state}
  end

  def handle_info(
        {:tcp, downstream_socket, data},
        state = %{upstream: %{socket: upstream_socket}, downstream: %{socket: downstream_socket},
          logger: %{socket: logger_socket} }
      ) do
    if state.packet_trace do
      Logger.debug("Up <- Down: #{inspect(data)}")
    end
    :gen_tcp.send(upstream_socket, data)
    :gen_tcp.send(logger_socket,"<<<"<>get_tstamp()<>">>>"<>Integer.to_string(byte_size(data)))
    # log the response timestamp and size
    {:noreply, state}
  end

  def handle_info(
        {:tcp_closed, upstream_socket},
        state = %{upstream: %{socket: upstream_socket}, downstream: %{socket: downstream_socket},
          logger: %{socket: nil}}
      ) do
    Logger.debug("Upstream socket closed, terminating proxy")
    :gen_tcp.close(downstream_socket)
    :gen_tcp.close(upstream_socket)
    {:stop, :normal, state}
  end

  def handle_info(
        {:tcp_closed, upstream_socket},
        state = %{upstream: %{socket: upstream_socket}, downstream: %{socket: downstream_socket},
          logger: %{socket: logger_socket}}
      ) do
    Logger.debug("Upstream socket closed, terminating proxy")
    :gen_tcp.close(downstream_socket)
    :gen_tcp.close(logger_socket)
    :gen_tcp.close(upstream_socket)
    {:stop, :normal, state}
  end

  def handle_info(
        {:tcp_closed, downstream_socket},
        state = %{upstream: %{socket: upstream_socket}, downstream: %{socket: downstream_socket},
          logger: %{socket: nil}}
      ) do
    Logger.warn("Downstream socket closed, terminating proxy")
    :gen_tcp.close(downstream_socket)
    :gen_tcp.close(upstream_socket)
    {:stop, :normal, state}
  end

  def handle_info(
        {:tcp_closed, downstream_socket},
        state = %{upstream: %{socket: upstream_socket}, downstream: %{socket: downstream_socket},
          logger: %{socket: logger_socket}}
      ) do
    Logger.warn("Downstream socket closed, terminating proxy")
    :gen_tcp.close(downstream_socket)
    :gen_tcp.close(logger_socket)
    :gen_tcp.close(upstream_socket)
    {:stop, :normal, state}
  end

  def handle_info(
        {:tcp_closed, logger_socket},
        state = %{logger: logger = %{socket: logger_socket}}
      ) do
    Logger.warn("Downstream logger socket closed, continuing without it")
    state = %{
      state |
      logger: %{
        logger | socket: nil
      }
    }
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.warn("Unexpected message: #{inspect(msg)}}")
    {:noreply, state}
  end

  defp get_tstamp() do
    to_string(:os.system_time(:millisecond))
  end
end
