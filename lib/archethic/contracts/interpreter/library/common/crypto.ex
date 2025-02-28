defmodule Archethic.Contracts.Interpreter.Library.Common.Crypto do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Library

  alias Archethic.Tag
  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.Contracts.Interpreter.Legacy
  alias Archethic.Contracts.Interpreter.Legacy.UtilsInterpreter

  use Tag

  @spec hash(binary(), binary()) :: binary()
  def hash(content, algo \\ "sha256")

  def hash(content, "keccak256"),
    do: UtilsInterpreter.maybe_decode_hex(content) |> ExKeccak.hash_256() |> Base.encode16()

  def hash(content, algo), do: Legacy.Library.hash(content, algo)

  @spec check_types(atom(), list()) :: boolean()
  def check_types(:hash, [first, second]) do
    (AST.is_binary?(first) || AST.is_variable_or_function_call?(first)) &&
      (AST.is_binary?(second) || AST.is_variable_or_function_call?(second))
  end

  def check_types(:hash, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(_, _), do: false
end
