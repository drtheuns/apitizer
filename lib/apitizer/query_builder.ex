defmodule Apitizer.QueryBuilder do
  @moduledoc """
  TODO

  TODO: Expression filtering (what is and isnt allowed?). Should be strict: not allowed unless declared allowed.
  TODO: Add schema attribute to simplify usage
  """
  import Ecto.Query, only: [from: 2, dynamic: 2]
  import Apitizer.Helpers

  defmacro __using__(_opts) do
    quote do
      import Apitizer.QueryBuilder

      def build(%Plug.Conn{} = conn, schema) do
        build(__MODULE__, conn, schema)
      end

      def before(query, context) do
        query
      end

      defoverridable before: 2
    end
  end

  def build(module, conn, schema) do
    context = Map.put(conn.assigns, :conn, conn)

    from(q in schema, [])
    |> module.before(context)
    |> apply_filters(context)
    |> preload(context, schema)
  end

  defp preload(query, context, schema) do
    from(q in query, preload: ^to_preload(context.conn, schema))
  end

  defp apply_filters(query, context) do
    context.conn.private
    |> Map.get(:apitizer_filters, [])
    |> Enum.reduce(query, fn filter, acc ->
      from(acc, where: ^interpret_filter_expr(filter))
    end)
  end

  defp interpret_filter_expr({op, expressions}) when op in [:and, :or] do
    Enum.reduce(expressions, op == :and, fn expr, dynamics ->
      interpret_operator(dynamics, op, expr)
    end)
  end

  defp interpret_operator(dynamics, :and, {op, expressions}) when op in [:and, :or] do
    dynamic([c], ^interpret_filter_expr({op, expressions}) and ^dynamics)
  end

  defp interpret_operator(dynamics, :or, {op, expressions}) when op in [:and, :or] do
    dynamic([c], ^interpret_filter_expr({op, expressions}) or ^dynamics)
  end

  defp interpret_operator(dynamics, :and, {:eq, field, value}) do
    dynamic([c], field(c, ^String.to_existing_atom(field)) == ^value and ^dynamics)
  end

  defp interpret_operator(dynamics, :or, {:eq, field, value}) do
    dynamic([c], field(c, ^String.to_existing_atom(field)) == ^value or ^dynamics)
  end

  defp interpret_operator(dynamics, :and, {:neq, field, value}) do
    dynamic([c], field(c, ^String.to_existing_atom(field)) != ^value and ^dynamics)
  end

  defp interpret_operator(dynamics, :or, {:neq, field, value}) do
    dynamic([c], field(c, ^String.to_existing_atom(field)) != ^value or ^dynamics)
  end

  defp interpret_operator(dynamics, :and, {:gt, field, value}) do
    dynamic([c], field(c, ^String.to_existing_atom(field)) > ^value and ^dynamics)
  end

  defp interpret_operator(dynamics, :or, {:gt, field, value}) do
    dynamic([c], field(c, ^String.to_existing_atom(field)) > ^value or ^dynamics)
  end

  defp interpret_operator(dynamics, :and, {:gte, field, value}) do
    dynamic([c], field(c, ^String.to_existing_atom(field)) >= ^value and ^dynamics)
  end

  defp interpret_operator(dynamics, :or, {:gte, field, value}) do
    dynamic([c], field(c, ^String.to_existing_atom(field)) >= ^value or ^dynamics)
  end

  defp interpret_operator(dynamics, :and, {:lt, field, value}) do
    dynamic([c], field(c, ^String.to_existing_atom(field)) < ^value and ^dynamics)
  end

  defp interpret_operator(dynamics, :or, {:lt, field, value}) do
    dynamic([c], field(c, ^String.to_existing_atom(field)) < ^value or ^dynamics)
  end

  defp interpret_operator(dynamics, :and, {:lte, field, value}) do
    dynamic([c], field(c, ^String.to_existing_atom(field)) <= ^value and ^dynamics)
  end

  defp interpret_operator(dynamics, :or, {:lte, field, value}) do
    dynamic([c], field(c, ^String.to_existing_atom(field)) <= ^value or ^dynamics)
  end

  defp interpret_operator(dynamics, :and, {:in, field, values}) do
    dynamic([c], field(c, ^String.to_existing_atom(field)) in ^values and ^dynamics)
  end

  defp interpret_operator(dynamics, :or, {:in, field, values}) do
    dynamic([c], field(c, ^String.to_existing_atom(field)) in ^values or ^dynamics)
  end

  defp interpret_operator(dynamics, _, _), do: dynamics
end
