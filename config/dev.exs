import Config

# config :logger, handle_sasl_reports: true
config :uniris,
       :mut_dir,
       System.get_env("UNIRIS_MUT_DIR", "data_#{System.get_env("UNIRIS_CRYPTO_SEED", "node1")}")

config :telemetry_poller, :default, period: 5_000

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

config :uniris, Uniris.BeaconChain.SlotTimer,
  # Every 10 seconds
  interval: "*/10 * * * * *"

config :uniris, Uniris.BeaconChain.SummaryTimer,
  # Every minute
  interval: "0 * * * * *"

config :uniris, Uniris.Bootstrap,
  reward_address:
    System.get_env(
      "UNIRIS_REWARD_ADDRESS",
      Base.encode16(<<0::8, :crypto.strong_rand_bytes(32)::binary>>)
    )
    |> Base.decode16!(case: :mixed)

config :uniris, Uniris.Bootstrap.Sync, out_of_sync_date_threshold: 60

config :uniris, Uniris.Crypto,
  root_ca_public_keys: [
    #  From `:crypto.generate_key(:ecdh, :secp256r1, "ca_root_key")`
    software:
      <<4, 210, 136, 107, 189, 140, 118, 86, 124, 217, 244, 69, 111, 61, 56, 224, 56, 150, 230,
        194, 203, 81, 213, 212, 220, 19, 1, 180, 114, 44, 230, 149, 21, 125, 69, 206, 32, 173,
        186, 81, 243, 58, 13, 198, 129, 169, 33, 179, 201, 50, 49, 67, 38, 156, 38, 199, 97, 59,
        70, 95, 28, 35, 233, 21, 230>>,
    tpm:
      <<4, 210, 136, 107, 189, 140, 118, 86, 124, 217, 244, 69, 111, 61, 56, 224, 56, 150, 230,
        194, 203, 81, 213, 212, 220, 19, 1, 180, 114, 44, 230, 149, 21, 125, 69, 206, 32, 173,
        186, 81, 243, 58, 13, 198, 129, 169, 33, 179, 201, 50, 49, 67, 38, 156, 38, 199, 97, 59,
        70, 95, 28, 35, 233, 21, 230>>
  ],
  software_root_ca_key: :crypto.generate_key(:ecdh, :secp256r1, "ca_root_key") |> elem(1)

config :uniris, Uniris.P2P.BootstrappingSeeds,
  # First node crypto seed is "node1"
  genesis_seeds:
    System.get_env(
      "UNIRIS_P2P_SEEDS",
      "127.0.0.1:3002:00001D967D71B2E135C84206DDD108B5925A2CD99C8EBC5AB5D8FD2EC9400CE3C98A:tcp"
    )

config :uniris, Uniris.Crypto.NodeKeystore,
  impl:
    (case System.get_env("UNIRIS_CRYPTO_NODE_KEYSTORE", "SOFTWARE") do
       "SOFTWARE" ->
         Uniris.Crypto.NodeKeystore.SoftwareImpl

       "TPM" ->
         Uniris.Crypto.NodeKeystore.TPMImpl
     end)

config :uniris, Uniris.Crypto.NodeKeystore.SoftwareImpl,
  seed: System.get_env("UNIRIS_CRYPTO_SEED", "node1")

config :uniris, Uniris.Governance.Pools,
  initial_members: [
    technical_council: [
      {"00001D967D71B2E135C84206DDD108B5925A2CD99C8EBC5AB5D8FD2EC9400CE3C98A", 1}
    ],
    ethical_council: [],
    foundation: [],
    uniris: []
  ]

config :uniris, Uniris.OracleChain.Scheduler,
  # Poll new changes every 10 seconds
  polling_interval: "*/10 * * * * *",
  # Aggregate chain at the 50th second
  summary_interval: "50 * * * * *"

config :uniris, Uniris.Networking.IPLookup, impl: Uniris.Networking.IPLookup.Static

config :uniris, Uniris.Reward.NetworkPoolScheduler,
  # At the 30th second
  interval: "30 * * * * *"

config :uniris, Uniris.Reward.WithdrawScheduler,
  # Every 10s
  interval: "*/10 * * * * *"

config :uniris, Uniris.SelfRepair.Scheduler,
  # Every minute
  interval: "5 * * * * * *"

config :uniris, Uniris.SharedSecrets.NodeRenewalScheduler,
  # At 40th second
  interval: "40 * * * * * *",
  application_interval: "0 * * * * * *"

config :uniris, Uniris.P2P.Endpoint,
  port: System.get_env("UNIRIS_P2P_PORT", "3002") |> String.to_integer()

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we use it
# with webpack to recompile .js and .css sources.
config :uniris, UnirisWeb.Endpoint,
  http: [port: System.get_env("UNIRIS_HTTP_PORT", "4000") |> String.to_integer()],
  server: true,
  debug_errors: true,
  check_origin: false,
  watchers: [
    node: [
      "node_modules/webpack/bin/webpack.js",
      "--mode",
      "development",
      "--watch-stdin",
      cd: Path.expand("../assets", __DIR__)
    ]
  ]
