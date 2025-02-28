defmodule Archethic.TransactionChain.Transaction.ValidationStampTest do
  use ArchethicCase

  import ArchethicCase, only: [current_protocol_version: 0]
  use ExUnitProperties

  alias Archethic.Crypto

  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  doctest ValidationStamp

  property "symmetric sign/valid validation stamp" do
    check all(
            proof_of_work <- StreamData.binary(length: 33),
            proof_of_integrity <- StreamData.binary(length: 33),
            proof_of_election <- StreamData.binary(length: 32),
            ledger_operations <- gen_ledger_operations()
          ) do
      pub = Crypto.last_node_public_key()

      assert %ValidationStamp{
               timestamp: DateTime.utc_now(),
               proof_of_work: proof_of_work,
               proof_of_integrity: proof_of_integrity,
               proof_of_election: proof_of_election,
               ledger_operations: ledger_operations,
               protocol_version: current_protocol_version()
             }
             |> ValidationStamp.sign()
             |> ValidationStamp.valid_signature?(pub)
    end
  end

  defp gen_ledger_operations do
    gen all(
          fee <- StreamData.positive_integer(),
          transaction_movements <- StreamData.list_of(gen_transaction_movement()),
          unspent_outputs <- StreamData.list_of(gen_unspent_outputs())
        ) do
      %LedgerOperations{
        fee: fee,
        transaction_movements: transaction_movements,
        unspent_outputs: unspent_outputs
      }
    end
  end

  defp gen_transaction_movement do
    gen all(
          to <- StreamData.binary(length: 33),
          amount <- StreamData.positive_integer(),
          type <-
            StreamData.one_of([
              StreamData.constant(:UCO),
              StreamData.tuple(
                {StreamData.constant(:token), StreamData.binary(length: 33),
                 StreamData.positive_integer()}
              )
            ])
        ) do
      %TransactionMovement{to: to, amount: amount, type: type}
    end
  end

  defp gen_unspent_outputs do
    gen all(
          from <- StreamData.binary(length: 33),
          amount <- StreamData.positive_integer(),
          timestamp <- StreamData.constant(DateTime.utc_now() |> DateTime.truncate(:millisecond)),
          type <-
            StreamData.one_of([
              StreamData.constant(:UCO),
              StreamData.tuple(
                {StreamData.constant(:token), StreamData.binary(length: 33),
                 StreamData.positive_integer()}
              )
            ])
        ) do
      %UnspentOutput{from: from, amount: amount, type: type, timestamp: timestamp}
    end
  end
end
