defmodule Apitizer.Interpreter do
  @moduledoc """
  Interprets a request using a query builder module.
  """
  import Ecto.Query
  import Apitizer.Utils

  alias Apitizer.{Context, Pagination, Parser, RenderTree}
  alias Apitizer.Builder.{Attribute, Association}

  @type option ::
          {:filter_key, String.t()}
          | {:sort_key, String.t()}
          | {:select_key, String.t()}
          | {:repo, atom()}
          | {:repo_function, (repo :: module(), Ecto.Queryable.t() -> map | list)}
          | {:max_depth, :infinite | pos_integer}
  @type options :: [option]

  @doc """
  Build the query based on the request.
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
  def one!(query_builder, id, %Plug.Conn{} = conn, opts \\ [])
      when is_atom(query_builder) and is_list(opts) do
    opts = Keyword.put_new(opts, :repo_function, fn query, %{repo: repo} -> repo.one!(query) end)
    build_one!(query_builder, id, from_conn(query_builder, conn, opts))
  end

  @doc """
  TODO
  """
  @spec paginate(module(), Plug.Conn.t(), options) :: map()
  def paginate(query_builder, %Plug.Conn{} = conn, opts \\ [])
      when is_atom(query_builder) and is_list(opts) do
    opts =
      Keyword.put_new(opts, :repo_function, fn query, %{repo: repo} ->
        repo.paginate(query, conn.params)
      end)

    build_paginate(query_builder, from_conn(query_builder, conn, opts))
  end

  @doc false
  def from_conn(query_builder, %Plug.Conn{} = conn, opts) do
    repo = option_or_config(opts, :repo, query_builder.__repo__)
    repo_function = Keyword.get(opts, :repo_function)
    filter_key = option_or_config(opts, :filter_key, "filter")
    sort_key = option_or_config(opts, :sort_key, "sort")
    select_key = option_or_config(opts, :select_key, "select")

    max_depth =
      case option_or_config(opts, :max_depth, 4) do
        :infinite ->
          :infinite

        number when is_integer(number) and number > 0 ->
          number

        _ ->
          raise ArgumentError,
            message: "The max depth must either be :infinite or a positive integer."
      end

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
      repo_function: repo_function,
      raw_filters: Map.get(conn.query_params, filter_key),
      raw_sort: Map.get(conn.query_params, sort_key),
      raw_select: Map.get(conn.query_params, select_key),
      parsed_filters: Parser.parse_filter(Map.get(conn.query_params, filter_key)),
      parsed_sort: Parser.parse_sort(Map.get(conn.query_params, sort_key)),
      parsed_select: Parser.parse_select(Map.get(conn.query_params, select_key)),
      assigns: Map.put(conn.assigns, :conn, conn),
      max_depth: max_depth
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

  def build_one!(query_builder, id, %Context{} = context) do
    query_builder
    |> build_query(context)
    |> where(id: ^id)
    |> call_repo_function(context)
    |> apply_transform(context)
  end

  def build_paginate(query_builder, %Context{} = context) do
    query_builder
    |> build_query(context)
    |> call_repo_function(context)
    |> Pagination.transform_entries(fn struct -> apply_transform(struct, context) end)
    |> Pagination.generate_response(context)
  end

  defp call_repo_function(query, %{repo_function: fun} = context) when is_function(fun, 2),
    do: fun.(query, context)

  defp call_repo_function(_query, _) do
    raise ArgumentError,
      message: "Expected the repo function to have an arity of 2 for the repo and the query"
  end

  defp build_render_tree(query_builder, context) do
    # render_tree = build_render_tree(query_builder, context.parsed_select, nil, nil, nil)
    render_tree = build_render_tree(query_builder, nil, context.parsed_select, context, 1)

    %{context | render_tree: render_tree}
  end

  defp build_render_tree(_, _, _, %{max_depth: max_depth}, current_depth)
       when is_integer(max_depth) and current_depth > max_depth,
       do: nil

  defp build_render_tree(query_builder, association, selects, context, depth) do
    {assoc, fields} =
      Enum.split_with(selects, fn
        {:assoc, _, _} -> true
        _ -> false
      end)

    # The query parser doesn't complain about ?select=*,id,name
    # so we need to make sure we don't get duplicate attributes.
    fields =
      case Enum.member?(fields, :all) do
        true ->
          query_builder.__attributes__() |> Enum.map(&query_builder.__attribute__/1)

        false ->
          Enum.reduce(fields, [], fn field, acc ->
            with {name, name_alias} <- name_and_alias(field),
                 %Attribute{} = attribute <- query_builder.__attribute__(name),
                 true <- may_select?(attribute.name, context) do
              [%{attribute | alias: name_alias} | acc]
            else
              _ -> acc
            end
          end)
      end

    children =
      Enum.reduce(assoc, %{}, fn {:assoc, assoc, assoc_selects}, acc ->
        with {name, name_alias} <- name_and_alias(assoc),
             %Association{} = assoc <- query_builder.__association__(name),
             true <- may_select?(assoc.name, query_builder, context),
             %RenderTree{} = child_tree <-
               build_render_tree(assoc.builder, assoc, assoc_selects, context, depth + 1) do
          Map.put(acc, name_alias, child_tree)
        else
          _ -> acc
        end
      end)

    %RenderTree{
      name: (association && association.name) || nil,
      key: (association && association.key) || nil,
      builder: query_builder,
      schema: query_builder.__schema__(),
      fields: fields,
      children: children,
      apidoc: (association && association.apidoc) || nil
    }
  end

  defp may_select?(field_or_assoc, %{render_tree: %{builder: builder}} = context),
    do: builder.may_select?(field_or_assoc, context)

  defp may_select?(field_or_assoc, query_builder, context) when is_atom(query_builder),
    do: query_builder.may_select?(field_or_assoc, context)

  defp may_see?(field_or_assoc, resource, query_builder, context) when is_atom(query_builder),
    do: query_builder.may_see?(field_or_assoc, resource, context)

  def apply_filters(query, %{parsed_filters: {and_or, expressions}} = context) do
    {query, dynamics} = do_apply_filters({query, and_or == :and}, and_or, expressions, context)

    from(q in query, where: ^dynamics)
  end

  def apply_filters(query, _context), do: query

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

  def apply_select(query, %{render_tree: %{fields: []}}), do: query

  def apply_select(query, %{render_tree: tree}) do
    # There are a couple of fields that we always need to load even if they're
    # not selected:
    #   - the primary key(s)
    #   - the foreign keys for the child trees.
    # otherwise we cannot properly preload stuff.

    primary_keys = tree.schema.__schema__(:primary_key)

    foreign_keys =
      Enum.map(tree.children, fn {name, _subtree} ->
        key = tree.builder.__association__(name).key
        tree.schema.__schema__(:association, key).owner_key
      end)

    selected_keys = Enum.map(tree.fields, & &1.key)
    fields = [primary_keys, foreign_keys, selected_keys] |> List.flatten() |> Enum.uniq()

    from(q in query, select: struct(q, ^fields))
  end

  def apply_sort(query, %{parsed_sort: sorts, render_tree: %{builder: builder}} = context) do
    Enum.reduce(sorts, query, fn {sort_direction, field}, query ->
      with {:sort, nil} <- {:sort, builder.sort(field, sort_direction, query, context)},
           %Attribute{} = attribute <- builder.__attribute__(field),
           true <- attribute.sortable do
        from(q in query, order_by: [{^sort_direction, field(q, ^attribute.key)}])
      else
        {:sort, updated_query} -> updated_query
        _ -> query
      end
    end)
  end

  def apply_preload(query, %{render_tree: tree} = context) do
    preload =
      Enum.map(tree.children, fn {_name, subtree} ->
        context = %{context | render_tree: subtree}
        new_query = from(q in subtree.schema) |> apply_select(context)

        {subtree.key, apply_preload(new_query, context)}
      end)

    from(q in query, preload: ^preload)
  end

  def apply_transform(resources, context) when is_list(resources) do
    Enum.map(resources, &apply_transform(&1, context))
  end

  # This only matches when we're dealing with a struct that is expected of this
  # render tree node. This filters out any possible pagination structs at the
  # cost of being less flexible.
  def apply_transform(
        %{__struct__: schema} = resource,
        %{render_tree: %{schema: schema}} = context
      ) do
    %{}
    |> transform_attributes(resource, context)
    |> transform_associations(resource, context)
  end

  defp transform_attributes(result, resource, %{render_tree: tree} = context) do
    Enum.reduce(tree.fields, result, fn attr, acc ->
      if may_see?(attr.name, resource, tree.builder, context) do
        value = tree.builder.transform(attr.name, Map.get(resource, attr.key), resource, context)
        Map.put(acc, attr.alias, value)
      else
        acc
      end
    end)
  end

  defp transform_associations(result, resource, %{render_tree: tree} = context) do
    Enum.reduce(tree.children, result, fn {name, subtree}, acc ->
      if may_see?(name, resource, tree.builder, context) do
        value =
          resource
          |> Map.get(subtree.key)
          |> apply_transform(%{context | render_tree: subtree})

        Map.put(acc, subtree.name, tree.builder.transform(name, value, resource, context))
      else
        acc
      end
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
