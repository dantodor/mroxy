

# Mroxy 
A proxy service to mediate access to SQL Server


## Project Goals

The objective of this project is to enable connections to MS SQL server with minimal latency penaly, while splitting the incoming traffic from the clients for logging and later analysis purposes



## Getting Started

_Get dependencies and compile:_
```
$ mix do deps.get, compile
```

_Run the Mroxy Server:_
```
$ mix run --no-halt
```

_Run with an attached session:_
```
$ iex -S mix
```

_Run Docker image_

Note: Chrome required a bump in shared memory allocation when running within
docker in order to function in a stable manner.

Exposes 1330, and 1331 (default ports for connection api and chrome proxy endpoint).
```
$ docker build . -t mroxy
$ docker run --shm-size 2G -p 1334:1334 mroxy
```


## Configuration

The configuration is designed to be friendly for containerisation as such uses
environment variables


### Configuration Variables

Ports, Proxy Host and Endpoint Scheme are managed via Env Vars.

| Variable                    | Default       | Desc.                                         |
| :------------------------   | :------------ | :---------------------------------------------|
| MROXY_PORT                  | 1334          | Port where to listen for incoming connections |
| DS_HOST                     | "127.0.0.1"   | Datasource hostname -> SQL Server instance    |
| DS_PORT                     | 1433          | SQL server listening port                     |
| LOGGER_HOST                 | "127.0.0.1"   | Host where logger is run                      |
| LOGGER_PORT                 | 8000          | port where logger instance is listening       |

## Components

### Proxy

An intermediary TCP proxy is in place to allow for monitoring of the _upstream_
client and _downstream_ MS SQL server connections, in order to clean up
resources after connections are closed.

`Mroxy.ProxyListener` - Incoming Connection Management & Delegation
* Listens for incoming connections on `MROXY_PORT`.
* Exposes `accept/1` function which will accept the next _upstream_ TCP connection and
  delegate the connection to a `ProxyServer` process along with the `proxy_opts`
  which enables the dynamic configuration of the _downstream_ connection.

`Mroxy.ProxyServer` - Dynamically Configured Transparent Proxy
* A dynamically configured transparent proxy.
* Manages delegated connection as the _upstream_ connection.
* Establishes _downstream_ connection based on `proxy_opts` at initialisation.

## Kubernetes
TBD
