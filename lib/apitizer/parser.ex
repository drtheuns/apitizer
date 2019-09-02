defmodule Apitizer.Parser do
  @moduledoc """
  Implements the parsers for the custom query expressions used in the API
  requests.

  ## Example

      iex> parse_filter("and(grade.gte.90,student.eq.true,or(age.gte.14,age.eq.null))")
      [and: [{:gte, "grade}, 90}, {:eq, "student", true}, {:or, [{:gte, "age", 14}, {:eq, "age", nil}]}]]
  """
  # See the `test/apitizer/parser_test.exs` for many more examples.
  import NimbleParsec

  # Order of these is importants, as "gt" would match before "gte".
  # the "in" operator is special as it requires a different value.
  @operators ["eq", "gte", "gt", "lte", "lt", "neq"]

  skip_space = ignore(ascii_char([?\s, ?\t, ?\r, ?\n]))

  quoted_value =
    ignore(string("\""))
    |> utf8_string([{:not, ?"}], min: 1)
    |> unwrap_and_tag(:quoted)
    |> ignore(string("\""))

  # accepts a a comma separated list like: (1, 2, 3) or (name, age, wow)
  list =
    ignore(string("("))
    |> repeat(skip_space)
    |> repeat(
      choice([
        quoted_value,
        utf8_string([{:not, ?,}, {:not, ?)}], min: 1)
      ])
      |> repeat(skip_space)
      |> optional(ignore(string(",")))
      |> repeat(skip_space)
    )
    |> map(:maybe_number)
    |> wrap()
    |> ignore(string(")"))

  # Examples:
  # student.eq.true -> {:eq, "student", true}
  # grade.gte.90    -> {:gte, "grade", 90}
  # id.in.(1,2,3)   -> {:in, "id", [1.0, 2.0, 3.0]}
  boolean_expr =
    utf8_string([{:not, ?,}, {:not, ?.}], min: 1)
    |> ignore(string("."))
    |> choice([
      string("in")
      |> ignore(string("."))
      |> concat(list),
      choice(Enum.map(@operators, fn op -> string(op) end))
      |> ignore(string("."))
      |> choice([
        quoted_value,
        # dot "." IS allowed here because of decimal values.
        utf8_string([{:not, ?,}, {:not, ?)}], min: 1)
      ])
    ])
    |> reduce(:to_boolean_expr)

  # Examples
  # and(expr1, expr2, or(expr3, expr4))
  defcombinatorp(
    :and_or_expression,
    choice([
      string("and") |> replace(:and),
      string("or") |> replace(:or)
    ])
    |> ignore(string("("))
    |> wrap(
      repeat(
        choice([
          parsec(:and_or_expression),
          boolean_expr
        ])
        |> optional(ignore(string(",")))
        |> repeat(skip_space)
      )
    )
    |> ignore(string(")"))
    |> reduce({List, :to_tuple, []})
    |> post_traverse(:remove_empty_expressions)
  )

  defparsecp(:filter, parsec(:and_or_expression))

  @doc """
  Parse a filter query to a list of expressions.

  Example:

  iex> parse_filter("and(student.eq.true,grade.gte.90)")
  [and: [{:eq, "student", true}, {:gte, "grade", 90}]]

  See `test/apitizer/parser_test.exs` for more examples.
  """
  def parse_filter(query_string) do
    case filter(query_string) do
      {:ok, fields, _, _, _, _} ->
        fields

      _ ->
        :error
    end
  end

  defp to_boolean_expr([field, operator, value]) do
    operator = String.to_atom(operator)
    {operator, field, cast_value(operator, value)}
  end

  defp cast_value(_, {:quoted, value}), do: value

  defp cast_value(op, "null") when op in [:eq, :neq], do: nil
  defp cast_value(op, "true") when op in [:eq, :neq], do: true
  defp cast_value(op, "false") when op in [:eq, :neq], do: false

  defp cast_value(op, value) when op in [:gte, :gt, :lte, :lt, :eq, :neq], do: maybe_number(value)

  defp cast_value(_, value), do: value

  defp maybe_number({:quoted, value}), do: value

  defp maybe_number(value) do
    # Best-effort casting to a number.
    case Integer.parse(value) do
      {number, ""} ->
        number

      {_, "." <> _} ->
        case Float.parse(value) do
          {number, ""} ->
            number

          _ ->
            value
        end

      :error ->
        value
    end
  end

  defp remove_empty_expressions(_rest, [{op, []}], context, _, _) when op in [:and, :or] do
    {[], context}
  end

  defp remove_empty_expressions(_rest, args, context, _, _) do
    {args, context}
  end
end
