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
    packet: 0,
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
    opts = Keyword.get(args, :proxy_opts)
    popts = Application.get_env(:mroxy, Mroxy.ProxyServer, [])
    # check args for packet_trace, otherwise check config
    packet_trace =
      Keyword.get(opts, :packet_trace, false) ||
        popts
        |> Keyword.get(:packet_trace, false)



    {:ok,
     %{
       upstream: %{
         socket: upstream_socket
       },
       downstream: %{
         downstream_host: Keyword.get(popts, :downstream_host),
         downstream_port: Keyword.get(popts, :downstream_port),
         tcp_opts: @downstream_tcp_opts,
         socket: nil
       },
       downstream_logger: %{
        downstream_logger_host: Keyword.get(popts, :downstream_logger_host),
        downstream_logger_port: Keyword.get(popts, :downstream_logger_port),
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
          downstream: downstream = %{downstream_host: downstream_host, downstream_port: downstream_port, socket: nil},
          downstream_logger: downstream_logger = %{downstream_logger_host: downstream_logger_host,
            downstream_logger_port: downstream_logger_port, socket: nil}
        })
  do
    if state.packet_trace do
      Logger.debug("Up -> PROXY [rescheduled]: #{inspect(data)}")
    end

    # Establish the downstream TCP connection
    # Add downstream connection information and socket to `ProxyServer` state
    # stop if we can't connect to main backend, continue working without logging backend
    case :gen_tcp.connect(to_charlist(downstream_host), downstream_port, @downstream_tcp_opts) do
      {:ok, down_socket} ->
        state = %{
          state |
          downstream: %{
            downstream | socket: down_socket
          }
        }
        Logger.debug("Downstream connection established")
        # Establish the downstream logger TCP connection
        # This must be handled differently from the normal downstream
        # If connection fails, we still continue to work, even if logger not available
        state = case :gen_tcp.connect(to_charlist(downstream_logger_host), downstream_logger_port, @logger_tcp_opts) do
          {:ok, down_logger_socket} ->
            %{
              state |
              downstream_logger: %{
                downstream_logger | socket: down_logger_socket
              }
            }
          _ -> state
        end

        Logger.debug("Downstream logger connection established")
        send(self(), msg)

        {:noreply, state}

      _ -> {:stop, :normal, state} # stop when we can't establish connection to main backend
    end

  end

   def handle_info(
        {:tcp, upstream_socket, data},
        state = %{upstream: %{socket: upstream_socket}, downstream: %{socket: downstream_socket},
          downstream_logger: %{socket: nil}, }
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
      downstream_logger: %{socket: downstream_logger_socket} }
  ) do
    if state.packet_trace do
      Logger.debug("Up -> Down: #{inspect(data)}")
    end

    :gen_tcp.send(downstream_socket, data)
    :gen_tcp.send(downstream_logger_socket, data)
    {:noreply, state}
  end

  def handle_info(
        {:tcp, downstream_socket, data},
        state = %{upstream: %{socket: upstream_socket}, downstream: %{socket: downstream_socket}}
      ) do
    if state.packet_trace do
      Logger.debug("Up <- Down: #{inspect(data)}")
    end

    :gen_tcp.send(upstream_socket, data)
    {:noreply, state}
  end

  def handle_info(
        {:tcp_closed, upstream_socket},
        state = %{upstream: %{socket: upstream_socket}, downstream: %{socket: downstream_socket},
        downstream_logger: %{socket: nil}}
      ) do
    Logger.debug("Upstream socket closed, terminating proxy")

    :gen_tcp.close(downstream_socket)
    :gen_tcp.close(upstream_socket)
    {:stop, :normal, state}
  end

  def handle_info(
    {:tcp_closed, upstream_socket},
    state = %{upstream: %{socket: upstream_socket}, downstream: %{socket: downstream_socket},
    downstream_logger: %{socket: downstream_logger_socket}}
  ) do
      Logger.debug("Upstream socket closed, terminating proxy")

      :gen_tcp.close(downstream_socket)
      :gen_tcp.close(downstream_logger_socket)
      :gen_tcp.close(upstream_socket)
      {:stop, :normal, state}
    end

  def handle_info(
        {:tcp_closed, downstream_socket},
        state = %{upstream: %{socket: upstream_socket}, downstream: %{socket: downstream_socket},
        downstream_logger: %{socket: nil}}
      ) do
    Logger.warn("Downstream socket closed, terminating proxy")

    :gen_tcp.close(downstream_socket)
    :gen_tcp.close(upstream_socket)
    {:stop, :normal, state}
  end

  def handle_info(
        {:tcp_closed, downstream_socket},
        state = %{upstream: %{socket: upstream_socket}, downstream: %{socket: downstream_socket},
        downstream_logger: %{socket: downstream_logger_socket}}
      ) do
    Logger.warn("Downstream socket closed, terminating proxy")

    :gen_tcp.close(downstream_socket)
    :gen_tcp.close(downstream_logger_socket)
    :gen_tcp.close(upstream_socket)
    {:stop, :normal, state}
  end

  def handle_info(
        {:tcp_closed, downstream_logger_socket},
        state = %{downstream_logger: downstream_logger = %{socket: downstream_logger_socket}}
      ) do
    Logger.warn("Downstream logger socket closed, continuing without it")

    state = %{
      state |
        downstream_logger: %{
          downstream_logger | socket: nil
      }
    }
    {:noreply, state}
  end

end
