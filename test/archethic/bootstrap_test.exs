defmodule ArchEthic.BootstrapTest do
  use ArchEthicCase

  alias ArchEthic.Crypto

  alias ArchEthic.BeaconChain.SlotTimer, as: BeaconSlotTimer
  alias ArchEthic.BeaconChain.SummaryTimer, as: BeaconSummaryTimer

  alias ArchEthic.Bootstrap

  alias ArchEthic.P2P
  alias ArchEthic.P2P.BootstrappingSeeds
  alias ArchEthic.P2P.Message.AcknowledgeStorage
  alias ArchEthic.P2P.Message.BootstrappingNodes
  alias ArchEthic.P2P.Message.EncryptedStorageNonce
  alias ArchEthic.P2P.Message.GetBootstrappingNodes
  alias ArchEthic.P2P.Message.GetLastTransactionAddress
  alias ArchEthic.P2P.Message.GetStorageNonce
  alias ArchEthic.P2P.Message.GetTransaction
  alias ArchEthic.P2P.Message.GetTransaction
  alias ArchEthic.P2P.Message.GetTransactionChain
  alias ArchEthic.P2P.Message.GetUnspentOutputs
  alias ArchEthic.P2P.Message.LastTransactionAddress
  alias ArchEthic.P2P.Message.ListNodes
  alias ArchEthic.P2P.Message.NewTransaction
  alias ArchEthic.P2P.Message.NodeList
  alias ArchEthic.P2P.Message.NotifyEndOfNodeSync
  alias ArchEthic.P2P.Message.Ok
  alias ArchEthic.P2P.Message.TransactionList
  alias ArchEthic.P2P.Message.UnspentOutputList
  alias ArchEthic.P2P.Node

  alias ArchEthic.Replication

  alias ArchEthic.SelfRepair.Scheduler, as: SelfRepairScheduler

  alias ArchEthic.SharedSecrets.NodeRenewalScheduler

  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.NodeMovement
  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Keys

  alias ArchEthic.PubSub

  alias ArchEthic.Utils

  import Mox

  setup do
    start_supervised!({BeaconSummaryTimer, interval: "0 0 * * * * *"})
    start_supervised!({BeaconSlotTimer, interval: "0 * * * * * *"})
    start_supervised!({SelfRepairScheduler, interval: "0 * * * * * *"})
    start_supervised!(BootstrappingSeeds)
    start_supervised!({NodeRenewalScheduler, interval: "0 * * * * * *"})

    MockDB
    |> stub(:write_transaction_chain, fn _ -> :ok end)

    on_exit(fn ->
      File.rm(Utils.mut_dir("priv/p2p/last_sync"))
    end)
  end

  describe "run/5" do
    test "should initialize the network when nothing is set before" do
      MockClient
      |> stub(:send_message, fn
        _, %GetLastTransactionAddress{address: address} ->
          {:ok, %LastTransactionAddress{address: address}}

        _, %GetUnspentOutputs{} ->
          {:ok, %UnspentOutputList{unspent_outputs: []}}

        _, %GetTransactionChain{} ->
          {:ok, %TransactionList{transactions: []}}

        _, %NotifyEndOfNodeSync{} ->
          {:ok, %Ok{}}
      end)

      {:ok, daily_nonce_key} =
        Agent.start_link(fn ->
          Application.get_env(:archethic, ArchEthic.Bootstrap.NetworkInit)
          |> Keyword.fetch!(:genesis_daily_nonce_seed)
          |> Crypto.generate_deterministic_keypair()
          |> elem(1)
        end)

      MockDB
      |> stub(:chain_size, fn _ -> 1 end)
      |> stub(:write_transaction_chain, fn
        [
          %Transaction{
            type: :node_shared_secrets,
            data: %TransactionData{keys: %Keys{authorized_keys: [keys], secrets: [secret]}}
          }
        ] ->
          encrypted_key = Map.get(keys, Crypto.last_node_public_key())
          aes_key = Crypto.ec_decrypt_with_last_node_key!(encrypted_key)
          <<encrypted_daily_nonce_seed::binary-size(60), _::binary>> = secret
          daily_nonce_seed = Crypto.aes_decrypt!(encrypted_daily_nonce_seed, aes_key)

          Agent.update(daily_nonce_key, fn _ ->
            daily_nonce_seed |> Crypto.generate_deterministic_keypair() |> elem(1)
          end)

        _ ->
          :ok
      end)

      MockCrypto
      |> stub(:sign_with_daily_nonce_key, fn data, _ ->
        Crypto.sign(data, Agent.get(daily_nonce_key, & &1))
      end)

      seeds = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: Crypto.first_node_public_key(),
          last_public_key: Crypto.last_node_public_key()
        }
      ]

      assert :ok =
               Bootstrap.run(
                 {127, 0, 0, 1},
                 3000,
                 :tcp,
                 seeds,
                 DateTime.utc_now(),
                 "00610F69B6C5C3449659C99F22956E5F37AA6B90B473585216CF4931DAF7A0AB45"
                 |> Base.decode16!()
               )

      assert [%Node{ip: {127, 0, 0, 1}, authorized?: true, transport: :tcp} | _] =
               P2P.list_nodes()

      assert 1 == Crypto.number_of_node_shared_secrets_keys()
    end
  end

  describe "run/5 with an initialized network" do
    setup do
      me = self()

      nodes = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          last_public_key:
            <<0, 0, 220, 205, 110, 4, 194, 222, 148, 194, 164, 97, 116, 158, 146, 181, 138, 166,
              24, 164, 86, 69, 130, 245, 19, 203, 19, 163, 2, 19, 160, 205, 9, 200>>,
          first_public_key:
            <<0, 0, 220, 205, 110, 4, 194, 222, 148, 194, 164, 97, 116, 158, 146, 181, 138, 166,
              24, 164, 86, 69, 130, 245, 19, 203, 19, 163, 2, 19, 160, 205, 9, 200>>,
          geo_patch: "AAA",
          network_patch: "AAA",
          authorized?: true,
          authorization_date: DateTime.utc_now(),
          available?: true,
          enrollment_date: DateTime.utc_now(),
          reward_address:
            <<245, 206, 118, 231, 188, 183, 250, 138, 217, 84, 176, 169, 37, 230, 8, 17, 147, 90,
              187, 118, 27, 143, 165, 86, 151, 130, 250, 231, 32, 155, 183, 79>>
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          last_public_key:
            <<0, 0, 186, 140, 57, 71, 50, 47, 229, 252, 24, 60, 6, 188, 83, 193, 145, 249, 111,
              74, 30, 113, 111, 191, 242, 155, 199, 104, 181, 21, 95, 208, 108, 146>>,
          first_public_key:
            <<0, 0, 186, 140, 57, 71, 50, 47, 229, 252, 24, 60, 6, 188, 83, 193, 145, 249, 111,
              74, 30, 113, 111, 191, 242, 155, 199, 104, 181, 21, 95, 208, 108, 146>>,
          geo_patch: "BBB",
          network_patch: "BBB",
          authorized?: true,
          authorization_date: DateTime.utc_now(),
          available?: true,
          enrollment_date: DateTime.utc_now(),
          reward_address:
            <<0, 122, 59, 37, 225, 0, 2, 24, 151, 241, 79, 158, 121, 16, 7, 168, 150, 94, 164, 74,
              201, 0, 202, 242, 185, 133, 85, 186, 73, 199, 223, 143>>
        }
      ]

      Enum.each(nodes, &P2P.add_and_connect_node/1)

      MockClient
      |> stub(:send_message, fn
        _, %GetBootstrappingNodes{} ->
          {:ok,
           %BootstrappingNodes{
             new_seeds: [
               Enum.at(nodes, 0)
             ],
             closest_nodes: [
               Enum.at(nodes, 1)
             ]
           }}

        _, %NewTransaction{transaction: tx} ->
          stamp = %ValidationStamp{
            timestamp: DateTime.utc_now(),
            proof_of_work: "",
            proof_of_integrity: "",
            ledger_operations: %LedgerOperations{
              node_movements: [
                %NodeMovement{
                  to: P2P.list_nodes() |> Enum.random() |> Map.get(:last_public_key),
                  amount: 1.0,
                  roles: [
                    :welcome_node,
                    :coordinator_node,
                    :cross_validation_node,
                    :previous_storage_node
                  ]
                }
              ]
            }
          }

          validated_tx = %{tx | validation_stamp: stamp}
          :ok = TransactionChain.write([validated_tx])
          :ok = Replication.ingest_transaction(validated_tx)
          :ok = Replication.acknowledge_storage(validated_tx, P2P.get_node_info())

          {:ok, %Ok{}}

        _, %GetStorageNonce{} ->
          {:ok,
           %EncryptedStorageNonce{
             digest:
               Crypto.ec_encrypt(:crypto.strong_rand_bytes(32), Crypto.last_node_public_key())
           }}

        _, %ListNodes{} ->
          {:ok, %NodeList{nodes: nodes}}

        _, %NotifyEndOfNodeSync{} ->
          send(me, :node_ready)
          {:ok, %Ok{}}

        _, %GetTransaction{address: address} ->
          {:ok,
           %Transaction{
             address: address,
             validation_stamp: %ValidationStamp{},
             cross_validation_stamps: [%{}]
           }}

        _, %AcknowledgeStorage{address: address} ->
          PubSub.notify_new_transaction(address)
          {:ok, %Ok{}}
      end)

      :ok
    end

    test "should add a new node" do
      seeds = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          last_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          network_patch: "AAA",
          reward_address:
            <<0, 122, 59, 37, 225, 0, 2, 24, 151, 241, 79, 158, 121, 16, 7, 168, 150, 94, 164, 74,
              201, 0, 202, 242, 185, 133, 85, 186, 73, 199, 223, 143>>
        }
      ]

      Enum.each(seeds, &P2P.add_and_connect_node/1)

      assert :ok =
               Bootstrap.run(
                 {127, 0, 0, 1},
                 3000,
                 :tcp,
                 seeds,
                 DateTime.utc_now(),
                 "00610F69B6C5C3449659C99F22956E5F37AA6B90B473585216CF4931DAF7A0AB45"
                 |> Base.decode16!()
               )

      assert Enum.any?(P2P.list_nodes(), &(&1.first_public_key == Crypto.first_node_public_key()))
    end

    test "should update a node" do
      seeds = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          last_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          network_patch: "AAA",
          reward_address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
        }
      ]

      Enum.each(seeds, &P2P.add_and_connect_node/1)

      assert :ok =
               Bootstrap.run(
                 {127, 0, 0, 1},
                 3000,
                 :tcp,
                 seeds,
                 DateTime.utc_now(),
                 "00610F69B6C5C3449659C99F22956E5F37AA6B90B473585216CF4931DAF7A0AB45"
                 |> Base.decode16!()
               )

      %Node{
        ip: {127, 0, 0, 1},
        first_public_key: first_public_key,
        last_public_key: last_public_key,
        transport: :tcp
      } = P2P.get_node_info()

      assert first_public_key == Crypto.first_node_public_key()
      assert last_public_key == Crypto.first_node_public_key()

      MockDB
      |> stub(:get_first_public_key, fn _ -> first_public_key end)

      assert :ok =
               Bootstrap.run(
                 {200, 50, 20, 10},
                 3000,
                 :tcp,
                 seeds,
                 DateTime.utc_now(),
                 "00610F69B6C5C3449659C99F22956E5F37AA6B90B473585216CF4931DAF7A0AB45"
                 |> Base.decode16!()
               )

      %Node{
        ip: {200, 50, 20, 10},
        first_public_key: first_public_key,
        last_public_key: last_public_key,
        transport: :tcp
      } = P2P.get_node_info()

      assert first_public_key == Crypto.first_node_public_key()
      assert last_public_key == Crypto.last_node_public_key()
    end

    test "should not bootstrap when you are the first node and you restart the node" do
      seeds = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          last_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          network_patch: "AAA",
          reward_address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
        }
      ]

      Enum.each(seeds, &P2P.add_and_connect_node/1)

      assert :ok =
               Bootstrap.run(
                 {127, 0, 0, 1},
                 3000,
                 :tcp,
                 seeds,
                 DateTime.utc_now(),
                 "00610F69B6C5C3449659C99F22956E5F37AA6B90B473585216CF4931DAF7A0AB45"
                 |> Base.decode16!()
               )

      assert %Node{ip: {127, 0, 0, 1}} = P2P.get_node_info!(Crypto.first_node_public_key())

      Process.sleep(200)

      assert :ok ==
               Bootstrap.run(
                 {127, 0, 0, 1},
                 3000,
                 :tcp,
                 seeds,
                 DateTime.utc_now(),
                 "00610F69B6C5C3449659C99F22956E5F37AA6B90B473585216CF4931DAF7A0AB45"
                 |> Base.decode16!()
               )

      Process.sleep(100)
    end
  end
end
