use Mix.Config

config :logger,
  utc_log: true,
  backends: []

config :farmbot, data_path: "/root"

# Disable tzdata autoupdates because it tries to dl the update file
# Before we have network or ntp.
config :tzdata, :autoupdate, :disabled

config :farmbot, Farmbot.Repo.A,
  adapter: Sqlite.Ecto2,
  loggers: [],
  database: "/root/repo-#{Mix.env()}-A.sqlite3"

config :farmbot, Farmbot.Repo.B,
  adapter: Sqlite.Ecto2,
  loggers: [],
  database: "/root/repo-#{Mix.env()}-B.sqlite3"

config :farmbot, Farmbot.System.ConfigStorage,
  adapter: Sqlite.Ecto2,
  loggers: [],
  database: "/root/config-#{Mix.env()}.sqlite3"

config :farmbot, ecto_repos: [Farmbot.Repo.A, Farmbot.Repo.B, Farmbot.System.ConfigStorage]

# Configure your our init system.
config :farmbot, :init, [
  # Load consolidated protocols
  Farmbot.Target.Protocols,

  # Autodetects if a Arduino is plugged in and configures accordingly.
  Farmbot.Firmware.UartHandler.AutoDetector,

  Farmbot.Target.ConfigMigration.BeforeNetwork,

  # Allows for first boot configuration.
  Farmbot.Target.Bootstrap.Configurator,

  # Start up Network
  Farmbot.Target.Network,

  # Wait for time time come up.
  Farmbot.Target.Network.WaitForTime,

  Farmbot.Target.ConfigMigration.AfterNetwork,

  Farmbot.Target.Uevent.Supervisor
]

config :farmbot, :transport, [
  # Farmbot.BotState.Transport.GenMQTT,
  Farmbot.BotState.Transport.AMQP,
  Farmbot.BotState.Transport.HTTP,
]

# Configure Farmbot Behaviours.
config :farmbot, :behaviour,
  authorization: Farmbot.Bootstrap.Authorization,
  system_tasks: Farmbot.Target.SystemTasks,
  firmware_handler: Farmbot.Firmware.StubHandler,
  update_handler: Farmbot.Target.UpdateHandler


config :nerves_firmware_ssh,
  authorized_keys: [
    File.read!(Path.join(System.user_home!, ".ssh/id_rsa.pub"))
  ]

config :nerves_init_gadget,
  address_method: :static

config :bootloader,
  init: [:nerves_runtime, :nerves_init_gadget],
  app: :farmbot


config :nerves_network,
  regulatory_domain: "US"

if Mix.Project.config[:target] == "rpi3" do
  config :nerves, :firmware, fwup_conf: "fwup_interim.conf"
end
