defmodule Apitizer.QueryBuilder.Interpreter do
  @moduledoc """
  Interprets a request using a query builder module.
  """
  import Ecto.Query
  import Apitizer.Utils

  alias Apitizer.{Parser, RenderTree}
  alias Apitizer.QueryBuilder.Context
  alias Apitizer.QueryBuilder.Builder.{Attribute, Association}

  @type option ::
          {:filter_key, String.t()}
          | {:sort_key, String.t()}
          | {:select_key, String.t()}
          | {:repo, atom()}
  @type options :: [option]

  @doc """
  TODO
  """
  @spec query(module(), Plug.Conn.t(), options) :: Ecto.Queryable.t()
  def query(query_builder, %Plug.Conn{} = conn, opts \\ [])
      when is_atom(query_builder) and is_list(opts) do
    build_query(query_builder, from_conn(query_builder, conn, opts))
  end

  @doc """
  TODO
  """
  @spec one!(module(), Plug.Conn.t(), options) :: map() | nil
  def one!(query_builder, %Plug.Conn{} = conn, opts \\ [])
      when is_atom(query_builder) and is_list(opts) do
    build_one!(query_builder, from_conn(query_builder, conn, opts))
  end

  @doc """
  TODO
  """
  @spec all(module(), Plug.Conn.t(), options) :: [map()]
  def all(query_builder, %Plug.Conn{} = conn, opts \\ [])
      when is_atom(query_builder) and is_list(opts) do
    build_all(query_builder, from_conn(query_builder, conn, opts))
  end

  @doc """
  TODO
  """
  @spec paginate(module(), Plug.Conn.t(), options) :: map()
  def paginate(query_builder, %Plug.Conn{} = conn, opts \\ [])
      when is_atom(query_builder) and is_list(opts) do
    build_paginate(query_builder, from_conn(query_builder, conn, opts))
  end

  defp from_conn(query_builder, %Plug.Conn{} = conn, opts) do
    repo = option_or_config(opts, :repo, query_builder.__repo__)
    filter_key = option_or_config(opts, :filter_key, "filter")
    sort_key = option_or_config(opts, :sort_key, "sort")
    select_key = option_or_config(opts, :select_key, "select")

    if repo == nil or !is_atom(repo) do
      raise ArgumentError,
        message: """
        Could not find a Repo to use. Set one on the module or pass it when calling the module.

            defmodule MyApp.UserBuilder do
              use Apitizer.QueryBuilder, schema: User, repo: MyApp.Repo
            end

        or

            UserBuilder.build(conn, repo: MyApp.Repo)

        got: #{inspect(repo)}
        """
    end

    context = %Context{
      filter_key: filter_key,
      sort_key: sort_key,
      select_key: select_key,
      repo: repo,
      raw_filters: Map.get(conn.query_params, filter_key),
      raw_sort: Map.get(conn.query_params, sort_key),
      raw_select: Map.get(conn.query_params, select_key),
      parsed_filters: Parser.parse_filter(Map.get(conn.query_params, filter_key)),
      parsed_sort: Parser.parse_sort(Map.get(conn.query_params, sort_key)),
      parsed_select: Parser.parse_select(Map.get(conn.query_params, select_key)),
      assigns: Map.put(conn.assigns, :conn, conn)
    }

    build_render_tree(query_builder, context)
  end

  def build_query(query_builder, %Context{} = context) do
    from(q in query_builder.__schema__)
    # First the filters.
    |> query_builder.before_filters(context)
    |> apply_filters(context)
    |> query_builder.after_filters(context)
    # ... the select
    |> query_builder.before_select(context)
    |> apply_select(context)
    |> query_builder.after_select(context)
    # ... the sorts
    |> query_builder.before_sort(context)
    |> apply_sort(context)
    |> query_builder.after_sort(context)
    # and finally the preloads.
    |> query_builder.before_preload(context)
    |> apply_preload(context)
    |> query_builder.after_preload(context)
  end

  def build_one!(query_builder, %Context{} = context) do
    query_builder
    |> build_query(context)
    |> context.repo.one!()
    |> apply_transform(context)
  end

  def build_all(query_builder, %Context{} = context) do
    query_builder
    |> build_query(context)
    |> context.repo.all()
    |> apply_transform(context)
  end

  def build_paginate(_query_builder, %Context{} = _context) do
    # query = build(query_builder, context)
  end

  defp build_render_tree(query_builder, context) do
    render_tree = build_render_tree(query_builder, context.parsed_select, nil, nil, nil)
    %{context | render_tree: render_tree}
  end

  defp build_render_tree(query_builder, fields, name, key, apidoc) do
    {assoc, fields} =
      Enum.split_with(fields, fn
        {:assoc, _, _} -> true
        _ -> false
      end)

    # The query parser doesn't complain about ?select=*,id,name
    # so we need to make sure we don't get duplicate attributes.
    fields =
      case Enum.member?(fields, :all) do
        true -> query_builder.__attributes__() |> Enum.map(&query_builder.__attribute__/1)
        false -> Enum.reduce(fields, [], &filter_fields(query_builder, name_and_alias(&1), &2))
      end

    %RenderTree{
      name: name,
      key: key,
      builder: query_builder,
      fields: fields,
      children: build_children(query_builder, assoc),
      apidoc: apidoc
    }
  end

  defp filter_fields(builder, {field, field_alias}, acc) do
    case builder.__attribute__(field) do
      %Attribute{} = attr -> [%{attr | alias: field_alias} | acc]
      _ -> acc
    end
  end

  defp build_children(builder, associations, acc \\ %{})
  defp build_children(_, [], acc), do: acc

  defp build_children(builder, [{:assoc, assoc, children} | tail], acc) do
    {name, name_alias} = name_and_alias(assoc)
    acc = build_child(builder.__association__(name), name_alias, children, acc)
    build_children(builder, tail, acc)
  end

  defp build_child(%Association{} = assoc, name, children, acc) do
    Map.put(acc, name, build_render_tree(assoc.builder, children, name, assoc.key, assoc.apidoc))
  end

  defp build_child(_, _, _, acc), do: acc

  defp apply_filters(query, %{parsed_filters: {and_or, expressions}} = context) do
    {query, dynamics} = do_apply_filters({query, and_or == :and}, and_or, expressions, context)

    from(q in query, where: ^dynamics)
  end

  defp apply_filters(query, _context), do: query

  defp do_apply_filters(query_and_dynamics, _, [], _), do: query_and_dynamics

  defp do_apply_filters(query_and_dynamics, and_or, [{op, field, value} | tail], context) do
    # This needs to happen depth first, otherwise the outer expression ends up
    # being the inner most part of the query. If everything were AND that'd be
    # fine, but it breaks OR
    {query, dynamics} = do_apply_filters(query_and_dynamics, and_or, tail, context)
    builder = context.render_tree.builder

    case builder.filter(field, op, value, query, dynamics, and_or, context) do
      nil ->
        if attr = builder.__attribute__(field) do
          {query, interpret_expr(dynamics, and_or, {op, attr.key, value})}
        else
          {query, dynamics}
        end

      {_query, _dynamics} = updated_values ->
        updated_values

      _ ->
        {query, dynamics}
    end
  end

  defp do_apply_filters({query, _}, parent_and_or, [{and_or, expressions} | tail], context) do
    {query, and_or == :and}
    |> do_apply_filters(and_or, expressions, context)
    |> do_apply_filters(parent_and_or, tail, context)
  end

  defp apply_select(query, %{render_tree: %{fields: []}}), do: query

  defp apply_select(query, %{render_tree: tree}) do
    # There are a couple of fields that we always need to load even if they're
    # not selected:
    #   - the primary key(s)
    #   - the foreign keys for the child trees.
    # otherwise we cannot properly preload stuff.

    ecto_schema = tree.builder.__schema__()
    primary_keys = ecto_schema.__schema__(:primary_key)

    foreign_keys =
      Enum.map(tree.children, fn {name, _subtree} ->
        key = tree.builder.__association__(name).key
        ecto_schema.__schema__(:association, key).owner_key
      end)

    selected_keys = Enum.map(tree.fields, & &1.key)
    fields = [primary_keys, foreign_keys, selected_keys] |> List.flatten() |> Enum.uniq()

    from(q in query, select: struct(q, ^fields))
  end

  defp apply_sort(query, %{parsed_sort: sorts, render_tree: %{builder: builder}} = context) do
    Enum.reduce(sorts, query, fn {sort_direction, field}, query ->
      case builder.sort(field, sort_direction, query, context) do
        nil ->
          case builder.__attribute__(field) do
            nil -> query
            attribute -> from(q in query, order_by: [{^sort_direction, field(q, ^attribute.key)}])
          end

        updated_query ->
          updated_query
      end
    end)
  end

  defp apply_preload(query, %{render_tree: tree} = context) do
    preload =
      Enum.map(tree.children, fn {_name, subtree} ->
        context = %{context | render_tree: subtree}
        new_query = from(q in subtree.builder.__schema__) |> apply_select(context)

        {subtree.key, apply_preload(new_query, context)}
      end)

    from(q in query, preload: ^preload)
  end

  defp apply_transform(resources, context) when is_list(resources) do
    Enum.map(resources, &apply_transform(&1, context))
  end

  defp apply_transform(resource, %{render_tree: tree} = context) when is_map(resource) do
    response =
      Enum.reduce(tree.fields, %{}, fn field, acc ->
        Map.put(acc, field.alias, Map.get(resource, field.key))
      end)

    Enum.reduce(tree.children, response, fn {_name, subtree}, acc ->
      Map.put(
        acc,
        subtree.name,
        apply_transform(Map.get(resource, subtree.key), %{context | render_tree: subtree})
      )
    end)
  end

  defp name_and_alias({:alias, name, name_alias}), do: {name, name_alias}
  defp name_and_alias(name) when is_binary(name), do: {name, name}

  defp interpret_expr(dynamics, _, {_, :*, _}), do: dynamics

  defp interpret_expr(dynamics, :and, {:eq, field, value}),
    do: dynamic([q], field(q, ^field) == ^value and ^dynamics)

  defp interpret_expr(dynamics, :and, {:neq, field, value}),
    do: dynamic([q], field(q, ^field) != ^value and ^dynamics)

  defp interpret_expr(dynamics, :and, {:gte, field, value}),
    do: dynamic([q], field(q, ^field) >= ^value and ^dynamics)

  defp interpret_expr(dynamics, :and, {:gt, field, value}),
    do: dynamic([q], field(q, ^field) > ^value and ^dynamics)

  defp interpret_expr(dynamics, :and, {:lte, field, value}),
    do: dynamic([q], field(q, ^field) <= ^value and ^dynamics)

  defp interpret_expr(dynamics, :and, {:lt, field, value}),
    do: dynamic([q], field(q, ^field) < ^value and ^dynamics)

  defp interpret_expr(dynamics, :and, {:in, field, values}),
    do: dynamic([q], field(q, ^field) in ^values and ^dynamics)

  defp interpret_expr(dynamics, :and, {:like, field, value}),
    do: dynamic([q], like(field(q, ^field), ^value) and ^dynamics)

  defp interpret_expr(dynamics, :and, {:ilike, field, value}),
    do: dynamic([q], ilike(field(q, ^field), ^value) and ^dynamics)

  defp interpret_expr(dynamics, :or, {:eq, field, value}),
    do: dynamic([q], field(q, ^field) == ^value or ^dynamics)

  defp interpret_expr(dynamics, :or, {:neq, field, value}),
    do: dynamic([q], field(q, ^field) != ^value or ^dynamics)

  defp interpret_expr(dynamics, :or, {:gte, field, value}),
    do: dynamic([q], field(q, ^field) >= ^value or ^dynamics)

  defp interpret_expr(dynamics, :or, {:gt, field, value}),
    do: dynamic([q], field(q, ^field) > ^value or ^dynamics)

  defp interpret_expr(dynamics, :or, {:lte, field, value}),
    do: dynamic([q], field(q, ^field) <= ^value or ^dynamics)

  defp interpret_expr(dynamics, :or, {:lt, field, value}),
    do: dynamic([q], field(q, ^field) < ^value or ^dynamics)

  defp interpret_expr(dynamics, :or, {:in, field, values}),
    do: dynamic([q], field(q, ^field) in ^values or ^dynamics)

  defp interpret_expr(dynamics, :or, {:like, field, value}),
    do: dynamic([q], like(field(q, ^field), ^value) or ^dynamics)

  defp interpret_expr(dynamics, :or, {:ilike, field, value}),
    do: dynamic([q], ilike(field(q, ^field), ^value) or ^dynamics)

  defp interpret_expr(dynamics, _, _), do: dynamics
end
