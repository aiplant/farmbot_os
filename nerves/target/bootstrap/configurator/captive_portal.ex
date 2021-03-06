defmodule Farmbot.Target.Bootstrap.Configurator.CaptivePortal do
  defmodule Hostapd do
    @moduledoc """
    Manages an OS process of hostapd.
    """

    defmodule State do
      @moduledoc false
      defstruct [:hostapd, :interface, :ip_addr]
    end

    use GenServer
    use Farmbot.Logger

    @hostapd_conf_file "hostapd.conf"
    @hostapd_pid_file "hostapd.pid"

    defp ensure_interface(interface) do
      unless interface in Nerves.NetworkInterface.interfaces() do
        Logger.debug 2, "Waiting for #{interface}: #{inspect Nerves.NetworkInterface.interfaces()}"
        Process.sleep(100)
        ensure_interface(interface)
      end
    end

    @doc ~s"""
      Example:
        Iex> Hostapd.start_link ip_address: "192.168.24.1",
        ...> manager: Farmbot.Network.Manager, interface: "wlan0"
    """
    def start_link(opts, gen_server_opts \\ []) do
      GenServer.start_link(__MODULE__, opts, gen_server_opts)
    end

    def init(opts) do
      # We want to know if something does.
      Process.flag(:trap_exit, true)
      interface = Keyword.fetch!(opts, :interface)
      Logger.busy(3, "Starting hostapd on #{interface}")
      ensure_interface(interface)

      {hostapd_port, hostapd_os_pid} = setup_hostapd(interface, "192.168.25.1")

      state = %State{
        hostapd: {hostapd_port, hostapd_os_pid},
        interface: interface,
        ip_addr: "192.168.25.1"
      }

      {:ok, state}
    end

    defp setup_hostapd(interface, ip_addr) do
      # Make sure the interface is in proper condition.
      :ok = hostapd_ip_settings_up(interface, ip_addr)
      # build the hostapd configuration
      hostapd_conf = build_hostapd_conf(interface, build_ssid())
      # build a config file
      File.mkdir!("/tmp/hostapd")
      File.write!("/tmp/hostapd/#{@hostapd_conf_file}", hostapd_conf)

      hostapd_cmd =
        "hostapd -P /tmp/hostapd/#{@hostapd_pid_file} " <> "/tmp/hostapd/#{@hostapd_conf_file}"

      hostapd_port = Port.open({:spawn, hostapd_cmd}, [:binary])
      hostapd_os_pid = hostapd_port |> Port.info() |> Keyword.get(:os_pid)
      {hostapd_port, hostapd_os_pid}
    end

    defp hostapd_ip_settings_up(interface, ip_addr) do
      :ok =
        "ip"
        |> System.cmd(["link", "set", "#{interface}", "up"])
        |> print_cmd

      :ok =
        "ip"
        |> System.cmd(["addr", "add", "#{ip_addr}/24", "dev", "#{interface}"])
        |> print_cmd

      :ok
    end

    defp hostapd_ip_settings_down(interface, ip_addr) do
      :ok =
        "ip"
        |> System.cmd(["link", "set", "#{interface}", "down"])
        |> print_cmd

      :ok =
        "ip"
        |> System.cmd(["addr", "del", "#{ip_addr}/24", "dev", "#{interface}"])
        |> print_cmd

      :ok =
        "ip"
        |> System.cmd(["link", "set", "#{interface}", "up"])
        |> print_cmd

      :ok
    end

    defp build_hostapd_conf(interface, ssid) do
      """
      interface=#{interface}
      ssid=#{ssid}
      hw_mode=g
      channel=6
      auth_algs=1
      wmm_enabled=0
      """
    end

    defp build_ssid do
      node_str = node() |> Atom.to_string()
      case node_str |> String.split("@") do
        [name, "farmbot-" <> id] ->
          name <> "-" <> id
        _ -> "Farmbot"
      end
    end

    defp kill(os_pid), do: :ok = "kill" |> System.cmd(["9", "#{os_pid}"]) |> print_cmd

    defp print_cmd({_, 0}), do: :ok

    defp print_cmd({res, num}) do
      Logger.error(2, "Encountered an error (#{num}): #{res}")
      :error
    end

    def handle_info({port, {:data, data}}, state) do
      {hostapd_port, _} = state.hostapd

      cond do
        port == hostapd_port ->
          handle_hostapd(data, state)

        true ->
          {:noreply, state}
      end
    end

    def handle_info(_, state), do: {:noreply, state}

    defp handle_hostapd(data, state) when is_bitstring(data) do
      Logger.debug(3, String.trim(data))
      {:noreply, state}
    end

    def terminate(_, state) do
      Logger.busy 3, "Stopping hostapd"
      {hostapd_port, hostapd_pid} = state.hostapd
      Logger.busy 3, "Killing hostapd PID."
      :ok = kill(hostapd_pid)
      Logger.busy 3, "Resetting ip settings."
      hostapd_ip_settings_down(state.interface, state.ip_addr)
      Logger.busy 3, "removing PID."
      File.rm_rf!("/tmp/hostapd")
      Logger.success 3, "Done."
      Port.close(hostapd_port)
      :ok
    rescue
      _e in ArgumentError -> :ok
    end
  end

  use GenServer
  use Farmbot.Logger
  @interface "wlan0"

  def start_link() do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    Logger.busy(3, "Starting captive portal.")
    {:ok, hostapd} = Hostapd.start_link(interface: @interface)
    dhcp_opts = [
      gateway: "192.168.25.1",
      netmask: "255.255.255.0",
      range: {"192.168.25.2", "192.168.25.100"},
      domain_servers: ["192.168.25.1"],
    ]
    {:ok, dhcp_server} = DHCPServer.start_link(@interface, dhcp_opts)
    {:ok, %{hostapd: hostapd, dhcp_server: dhcp_server}}
  end

  def terminate(_, state) do
    Logger.busy 3, "Stopping captive portal GenServer."
    Logger.busy 3, "Stopping DHCP GenServer."
    GenServer.stop(state.dhcp_server, :normal)
    Logger.busy 3, "Stopping Hostapd GenServer."
    GenServer.stop(state.hostapd, :normal)
  end
end
