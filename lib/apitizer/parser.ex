defmodule Apitizer.Parser do
  @moduledoc """
  Implements the parsers for all the expressions that are allowed on the
  request: filter, select and sort.

  ## Filters

  Apitizer is able to parse relatively complex filter expressions and convert it
  to an Ecto query. The expression syntax is based on that of
  [PostgREST](http://postgrest.org/en/v6.0/api.html#horizontal-filtering-rows).

  Following are some examples of filter expressions:

    * `id.eq.5`
    * `and(name.ilike."test", or(id.in.(10,11,12), role.eq.admin))`
    * `*.search.hello world`

  Features:

    * The first-most expression does not need to be wrapped in `and()`, this
      will happen automatically. So `id.eq.5` and `and(id.eq.5)` are the same.
    * Spaces are optional in most locations.
    * Values can be quoted with `"`. If the value must contain a `"` itself, it
      can be quoted like: `\\"`
    * It accepts `:*` as a catch-all field. This can be useful when applying a
      filter to the entire resource, rather than some specific field, for
      example, a search over multiple fields. These types of filters must be
      explicitly implemented in the query builder.

  Limitations:

    * It does not accept custom operators. See `t:filter_operator/0` for a list
      of supported operators.

  ## Selects

  The select parser is used by the query builder to determine which fields to
  show and select in a query. Some examples:

    * `*`: select everything. This is the default.
    * `id,name,posts(*,comments(id,body))`: select the `id`, `name`, every field on the
      related `posts` and the `id` and `body` from those posts' comments.
    * `identifier:id,name,BlogPosts:posts(*)` select the `id`, `name` and `related`
      posts and alias the `id` to `identifier`, and alias the `posts` to `BlogPosts`.

  Features:

    * Accepts `*` to mean all fields.
    * Accepts relationships and fields on those relationships through parenthesis.
    * Accepts aliases for fields, which the query builder will use as key when
      returning a response.
    * Spaces are optional.
  """
  import NimbleParsec

  @type filter_and_or :: {:and | :or, [filter_expression | filter_and_or]}
  @type filter_expression :: {Apitizer.operator(), filter_field, filter_value}
  @type filter_field :: :* | String.t()
  @type filter_value :: String.t() | integer() | float()

  @type select_field :: String.t() | select_assoc | select_alias
  @type select_assoc :: {:assoc, String.t() | select_alias, [select_field]}
  @type select_alias :: {:alias, String.t(), String.t()}

  @type sort :: {Apitizer.sort_direction(), field :: String.t()}

  @doc """
  Parses a filter expressions as would be passed on the request.

  ## Example

      iex> parse_filter("priority.eq.4,or(id.in.(1,2,3),id.eq.5)")
      {:and, [{:eq, "priority", 4}, {:or, [{:in, "id", [1,2,3]}, {:eq, "id", 5}]}]}
  """
  @spec parse_filter(String.t()) :: filter_and_or
  def parse_filter(query_string) do
    case parse(&filter/1, query_string, [[]]) do
      [{_, _} = and_or_expression] -> and_or_expression
      _ -> []
    end
  end

  @doc """
  Parses a select expressions as would be passed on the request.

  ## Example

      iex> parse_select("id,name,posts(*,reactions:comments(*))")
      ["id", "name", {:assoc, "posts", [:all, {:assoc, {:alias, "comments", "reactions"}, [:all]}]}]
  """
  @spec parse_select(String.t()) :: [select_field]
  def parse_select(query_string), do: parse(&select/1, query_string, [:all])

  @doc """
  Parses a sort expressions as would be passed on the request.

  ## Example

      iex> parse_sort("name.asc,id.desc")
      [{:asc, "name"}, {:desc, "id"}]
      iex> parse_sort("name")
      [{:asc, "name"}]
  """
  @spec parse_sort(String.t()) :: [sort]
  def parse_sort(query_string), do: parse(&sort/1, query_string, [])

  defp parse(_parser, "", default), do: default
  defp parse(_parser, nil, default), do: default

  defp parse(parser, query_string, default) when is_binary(query_string) do
    parse_or_default(parser.(query_string), default)
  end

  defp parse(_parser, _query_string, default), do: default

  defp parse_or_default({:ok, [], _, _, _, _}, default), do: default
  defp parse_or_default({:ok, fields, _, _, _, _}, _), do: fields
  defp parse_or_default({:ok, value}, _), do: value

  defp sort(query_string) do
    sorts =
      query_string
      |> String.split(",", trim: true)
      |> Enum.map(fn value ->
        case String.split(value, ".", parts: 2, trim: true) do
          [field] -> {:asc, field}
          [field, "asc"] -> {:asc, field}
          [field, "desc"] -> {:desc, field}
          [field, _] -> {:asc, field}
        end
      end)

    {:ok, sorts}
  end

  # Order of these is importants, as "gt" would match before "gte".
  # the "in" operator is special as it requires a different value.
  @operators ["eq", "gte", "gt", "lte", "lt", "neq", "search", "ilike", "like", "contains"]

  skip_space = ignore(ascii_char([?\s, ?\t, ?\r, ?\n]))

  maybe_comma =
    repeat(skip_space)
    |> optional(ignore(string(",")))
    |> repeat(skip_space)

  quoted_value =
    ignore(string("\""))
    # Use repeat rather than utf8_string(_, min: 1) to implement support for
    # escaping double quotes.
    |> repeat(
      choice([
        # Escaped double quotes here.
        string(~S(\")) |> replace(?"),
        utf8_char([{:not, ?"}])
      ])
    )
    |> reduce({List, :to_string, []})
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
      |> concat(maybe_comma)
    )
    |> map(:maybe_number)
    |> wrap()
    |> ignore(string(")"))

  # Examples:
  # student.eq.true -> {:eq, "student", true}
  # grade.gte.90    -> {:gte, "grade", 90}
  # id.in.(1,2,3)   -> {:in, "id", [1, 2, 3]}
  boolean_expr =
    choice([
      string("*") |> replace(:*),
      utf8_string([{:not, ?,}, {:not, ?.}], min: 1)
    ])
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
        |> concat(maybe_comma)
      )
    )
    |> ignore(string(")"))
    |> reduce({List, :to_tuple, []})
    |> post_traverse(:remove_empty_expressions)
  )

  defparsecp(
    :filter,
    choice([
      parsec(:and_or_expression),
      repeat(
        choice([
          parsec(:and_or_expression),
          boolean_expr
        ])
        |> concat(maybe_comma)
      )
      |> tag(:and)
    ])
  )

  field_identifier = utf8_string([{:not, ?,}, {:not, ?\s}, {:not, ?(}, {:not, ?)}], min: 1)

  field_alias =
    utf8_string([{:not, ?,}, {:not, ?:}, {:not, ?\s}, {:not, ?(}, {:not, ?)}], min: 1)
    |> ignore(string(":"))
    |> unwrap_and_tag(:alias)

  defcombinatorp(
    :field,
    choice([
      string("*") |> replace(:all),
      repeat(skip_space)
      |> optional(field_alias)
      |> concat(field_identifier)
      |> repeat(skip_space)
      |> wrap()
      |> optional(
        ignore(string("("))
        |> repeat(parsec(:field) |> concat(maybe_comma))
        |> ignore(string(")"))
        |> tag(:assoc)
      )
      |> post_traverse(:unwrap_alias)
    ])
  )

  defparsecp(
    :select,
    repeat(
      parsec(:field)
      |> concat(maybe_comma)
    )
  )

  defp unwrap_alias(_rest, [{:assoc, fields}, [assoc]], context, _line, _offset) do
    {[{:assoc, assoc, fields}], context}
  end

  defp unwrap_alias(
         _rest,
         [{:assoc, fields}, [{:alias, assoc_alias}, assoc]],
         context,
         _line,
         _offset
       ) do
    {[{:assoc, {:alias, assoc, assoc_alias}, fields}], context}
  end

  defp unwrap_alias(_rest, [[no_alias]], context, _line, _offset) do
    {[no_alias], context}
  end

  defp unwrap_alias(_rest, [[{:alias, field_alias}, field]], context, _line, _offset) do
    {[{:alias, field, field_alias}], context}
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
