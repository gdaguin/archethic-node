defmodule Archethic.Contracts.Interpreter.ConditionValidator do
  @moduledoc """
  This is pretty much a copy of Legacy.ConditionInterpreter.
  The difference is where the scope is stored (process dict VS global variable)

  """
  alias Archethic.Contracts.ContractConditions, as: Conditions
  alias Archethic.Contracts.ContractConstants, as: Constants
  alias Archethic.Contracts.Interpreter
  alias Archethic.Contracts.Interpreter.Scope

  require Logger

  @doc """
  Determines if the conditions of a contract are valid from the given constants
  """
  @spec valid_conditions?(Conditions.t(), map()) :: boolean()
  def valid_conditions?(conditions = %Conditions{}, constants = %{}) do
    # Apply some transformations to the transactions
    # We do it here because the Constants module is still used by InterpreterLegacy
    constants =
      constants
      |> Constants.map_transactions(&Constants.stringify_transaction/1)
      |> Constants.map_transactions(&Constants.cast_transaction_amount_to_float/1)

    conditions
    |> Map.from_struct()
    |> Enum.all?(fn {field, condition} ->
      field = Atom.to_string(field)

      case validate_condition({field, condition}, constants) do
        {_, true} ->
          true

        {_, false} ->
          value = get_constant_value(constants, field)

          Logger.debug(
            "Invalid condition for `#{inspect(field)}` with the given value: `#{inspect(value)}` - condition: #{inspect(condition)}"
          )

          false
      end
    end)
  end

  defp get_constant_value(constants, field) do
    case get_in(constants, [
           Access.key("transaction", %{}),
           Access.key(field, "")
         ]) do
      "" ->
        get_in(constants, ["next", field])

      value ->
        value
    end
  end

  defp validate_condition({"origin_family", _}, _) do
    # Skip the verification
    # The Proof of Work algorithm will use this condition to verify the transaction
    {"origin_family", true}
  end

  defp validate_condition({"address", nil}, _) do
    # Skip the verification as the address changes for each transaction
    {"address", true}
  end

  defp validate_condition({"previous_public_key", nil}, _) do
    # Skip the verification as the previous public key changes for each transaction
    {"previous_public_key", true}
  end

  defp validate_condition({"timestamp", nil}, _) do
    # Skip the verification as timestamp changes for each transaction
    {"timestamp", true}
  end

  defp validate_condition({"type", nil}, %{
         "previous" => %{"type" => previous_type},
         "next" => %{"type" => next_type}
       }) do
    {"type", previous_type == next_type}
  end

  defp validate_condition({"content", nil}, %{"previous" => _, "next" => %{"content" => ""}}) do
    # Skip the verification when it's the default type
    {"content", true}
  end

  defp validate_condition(
         {"code", nil},
         %{
           "next" => %{"code" => next_code},
           "previous" => %{"code" => prev_code}
         }
       ) do
    prev_ast = prev_code |> Interpreter.sanitize_code(ignore_meta?: true)
    next_ast = next_code |> Interpreter.sanitize_code(ignore_meta?: true)

    {"code", prev_ast == next_ast}
  end

  # Validation rules for inherit constraints
  defp validate_condition({field, nil}, %{"previous" => prev, "next" => next}) do
    {field, Map.get(prev, field) == Map.get(next, field)}
  end

  defp validate_condition({field, condition}, constants = %{"previous" => _, "next" => next}) do
    result = evaluate_condition(condition, constants)

    if is_boolean(result) do
      {field, result}
    else
      {field, Map.get(next, field) == result}
    end
  end

  # Validation rules for incoming transaction
  defp validate_condition({field, nil}, %{"transaction" => _}) do
    # Skip the validation if no transaction conditions are provided
    {field, true}
  end

  defp validate_condition(
         {field, condition},
         constants = %{"transaction" => transaction}
       ) do
    result = evaluate_condition(condition, constants)

    if is_boolean(result) do
      {field, result}
    else
      {field, Map.get(transaction, field) == result}
    end
  end

  defp evaluate_condition(ast, constants) do
    # reset scope and set constants
    Scope.execute(ast, constants)
  end
end
