defmodule Apitizer.QueryBuilder do
  @moduledoc """
  TODO
  """
  import Ecto.Query
  alias Apitizer.RenderTree
  alias Apitizer.Parser

  defmodule Attribute do
    defstruct [:name, :sortable, :operators, :key, :alias]
  end

  defmodule Association do
    defstruct [:name, :builder, :key]
  end

  @doc """
  Defines a new attribute to be visible to the client.

  The name of the attribute is required and will be used for the output.

  ## Options

    * `:key`: the key to use on the schema to fetch the attribute. Defaults to
      the name given to the attribute. This option can be used when you want to
      decouple the name of the attribute from the struct key.
    * `:operators`: the operators that the client is allowed to filter on for
      this attribute. For more information, look at the "Operators" section of
      the module doc.
    * `:sortable`: whether or not the client is allowed to sort on this
      attribute.
  """
  defmacro attribute(name, opts \\ []) do
    quote do
      Apitizer.QueryBuilder.__attribute__(__MODULE__, unquote(name), unquote(opts))
    end
  end

  @doc """
  Defines an assocation that can be included in the response.

  For more information, see the "Includes" section of the documentation.
  The `builder` parameter expects another query builder module.

  ## Options

    * `:key`: the key on the struct to fetch the association from.
      This is the same as the `:key` option on `attribute/2`.
  """
  defmacro association(name, builder, opts \\ []) do
    quote do
      Apitizer.QueryBuilder.__association__(
        __MODULE__,
        unquote(name),
        unquote(builder),
        unquote(opts)
      )
    end
  end

  # defmacro filter(name, operator, value, query, assigns, do: block) do
  #   quote do
  #     Apitizer.QueryBuilder.__filter__(__MODULE__, unquote(name), unquote(operator))
  #   end
  # end

  def all(builder, %Plug.Conn{} = conn, opts \\ []) do
    tree = build_render_tree(builder, conn, opts)
    repo = Keyword.get(opts, :repo, builder.__repo__)
    query = from(q in builder.__schema__)

    context =
      conn.assigns
      |> Map.put(:conn, conn)

    filters =
      conn.query_params
      |> Map.get(Keyword.get(opts, :filter_key, "filter"))
      |> Parser.parse_filter()
      |> hd()

    # hd() here, because there's always only one top-level query: {and|or, expressions}

    unless is_atom(repo) and repo != nil do
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

    query
    |> builder.before_filters(context)
    |> apply_filters(filters, tree)
    |> apply_select(tree)
    |> apply_preload(tree)
    |> repo.all()
    |> apply_transform(tree)
  end

  defp build_render_tree(builder, %Plug.Conn{} = conn, opts) do
    fields =
      conn.query_params
      |> Map.get(Keyword.get(opts, :select_key, "select"))
      |> Parser.parse_select()

    build_render_tree(builder, nil, nil, fields)
  end

  defp build_render_tree(builder, name, key, fields) do
    {assoc, fields} =
      Enum.split_with(fields, fn
        {:assoc, _, _} -> true
        _ -> false
      end)

    # The query parser doesn't complain about ?select=*,id,name
    # so we need to make sure we don't get duplicate attributes.
    fields =
      case Enum.member?(fields, :all) do
        true -> builder.__attributes__() |> Enum.map(&builder.__attribute__/1)
        false -> Enum.reduce(fields, [], &get_field(builder, &1, &2))
      end

    children =
      Enum.reduce(assoc, %{}, fn {:assoc, assoc_name, assoc_fields}, acc ->
        {assoc_name, assoc_alias} =
          case assoc_name do
            {:alias, assoc_name, assoc_alias} -> {assoc_name, assoc_alias}
            assoc_name -> {assoc_name, assoc_name}
          end

        case builder.__association__(assoc_name) do
          nil ->
            acc

          assoc ->
            subtree = build_render_tree(assoc.builder, assoc_alias, assoc.key, assoc_fields)
            Map.put(acc, assoc.name, subtree)
        end
      end)

    RenderTree.new(name, key, builder, fields, children)
  end

  defp get_field(module, {:alias, field, field_alias}, acc) do
    case module.__attribute__(field) do
      nil -> acc
      attr -> [%{attr | alias: field_alias} | acc]
    end
  end

  defp get_field(module, field, acc) do
    case module.__attribute__(field) do
      nil -> acc
      attr -> [attr | acc]
    end
  end

  defp apply_select(query, %{fields: []}), do: query

  defp apply_select(query, %{fields: fields, builder: builder} = tree) do
    # There are a couple of fields that we always need to load even if they're
    # not selected:
    #   - the primary key(s)
    #   - the foreign keys for the child trees.
    # otherwise we cannot properly preload stuff.

    ecto_schema = builder.__schema__()
    primary_keys = ecto_schema.__schema__(:primary_key)

    foreign_keys =
      Enum.map(tree.children, fn {name, _subtree} ->
        key = builder.__association__(name).key
        ecto_schema.__schema__(:association, key).owner_key
      end)

    selected_keys = Enum.map(fields, & &1.key)
    fields = [primary_keys, foreign_keys, selected_keys] |> List.flatten() |> Enum.uniq()

    from(q in query, select: struct(q, ^fields))
  end

  defp apply_filters(query, {and_or, expressions}, tree) do
    dynamics = apply_filters(and_or != :and, and_or, expressions, tree)
    from(q in query, where: ^dynamics)
  end

  defp apply_filters(query, _, _), do: query

  defp apply_filters(dynamics, _, [], _), do: dynamics

  defp apply_filters(dynamics, and_or, [{op, field, value} | tail], tree) do
    # This needs to happen depth first, otherwise the outer expression ends up
    # being the inner most part of the query. If everything were AND that'd be
    # fine, but it breaks OR
    attr = tree.builder.__attribute__(field)
    dynamics = apply_filters(dynamics, and_or, tail, tree)

    if Enum.member?(attr.operators, op) do
      interpret_expr(dynamics, and_or, {op, attr.key, value})
    else
      dynamics
    end
  end

  defp apply_filters(dynamics, parent_and_or, [{and_or, expr} | tail], tree) do
    dynamics
    |> apply_filters(and_or, expr, tree)
    |> apply_filters(parent_and_or, tail, tree)
  end

  defp apply_transform(resources, tree) when is_list(resources) do
    Enum.map(resources, &apply_transform(&1, tree))
  end

  defp apply_transform(resource, tree) when is_map(resource) do
    response =
      Enum.reduce(tree.fields, %{}, fn field, acc ->
        Map.put(acc, field.alias, Map.get(resource, field.key))
      end)

    Enum.reduce(tree.children, response, fn {_name, subtree}, acc ->
      Map.put(acc, subtree.name, apply_transform(Map.get(resource, subtree.key), subtree))
    end)
  end

  defp apply_preload(query, tree) do
    preload =
      Enum.map(tree.children, fn {name, subtree} ->
        new_query = from(q in subtree.builder.__schema__) |> apply_select(subtree)
        {name, apply_preload(new_query, subtree)}
      end)

    case preload do
      [] -> query
      _ -> from(q in query, preload: ^preload)
    end
  end

  @doc false
  def __attribute__(module, name, opts) do
    opts =
      opts
      |> Keyword.put_new(:operators, Module.get_attribute(module, :operators))
      |> Keyword.put_new(:sortable, false)
      |> Keyword.put_new(:key, name)
      |> Keyword.put(:name, name)
      |> Keyword.put(:alias, name)

    struct = struct(Attribute, opts) |> Macro.escape()

    Module.put_attribute(module, :apitizer_attributes, {name, struct})
  end

  @doc false
  def __association__(module, name, builder, opts) do
    opts =
      opts
      |> Keyword.put(:name, name)
      |> Keyword.put(:builder, builder)
      |> Keyword.put_new(:key, name)

    struct = struct(Association, opts) |> Macro.escape()

    Module.put_attribute(module, :apitizer_associations, {name, struct})
  end

  @doc false
  defmacro __using__(opts) do
    schema = Keyword.get(opts, :schema) |> expand_alias(__CALLER__)
    repo = Keyword.get(opts, :repo) |> expand_alias(__CALLER__)

    unless is_atom(schema) and schema != nil do
      raise ArgumentError,
        message: """
        Expected a schema to be given to the query builder, for example:

            defmodule MyApp.UserBuilder do
              use Apitizer.QueryBuilder, schema: MyApp.User
            end

        got #{inspect(schema)}
        """
    end

    quote do
      import Apitizer.QueryBuilder

      @operators [:eq, :neq, :gte, :gt, :lte, :lt, :in]

      Module.register_attribute(__MODULE__, :apitizer_attributes, accumulate: true)
      Module.register_attribute(__MODULE__, :apitizer_associations, accumulate: true)
      Module.register_attribute(__MODULE__, :apitizer_filters, accumulate: true)
      Module.register_attribute(__MODULE__, :apitizer_sorts, accumulate: true)

      def __schema__, do: unquote(schema)
      def __repo__, do: unquote(repo)

      # def build(conn, opts \\ []), do: build(__MODULE__, conn, opts)
      def all(conn, opts \\ []), do: all(__MODULE__, conn, opts)

      def before_filters(query, context) do
        query
      end

      defoverridable before_filters: 2

      @before_compile Apitizer.QueryBuilder
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    attributes = Module.get_attribute(env.module, :apitizer_attributes) |> Enum.reverse()
    associations = Module.get_attribute(env.module, :apitizer_associations)
    # filters = Module.get_attribute(env.module, :apitizer_filters)
    # sorts = Module.get_attribute(env.module, :apitizer_sorts)

    quote do
      unquote(compile(:attribute, attributes))
      unquote(compile(:association, associations))
      # unquote(compile(:filter, filters))
      # unquote(compile(:sort, sorts))
    end
  end

  # Compiles all the different attributes, associations, filters, etc. to
  # introspectable functions. Everything should be "queryable" by name as either
  # a string or an atom (e.g. __attribute__(:name) & __attribute__("name"))
  # and the full list of keys can be fetched using the plural, e.g.:
  # __attributes__, __filters__, etc
  defp compile(module_attribute_name, module_attribute_values) do
    singular = :"__#{module_attribute_name}__"
    plural = :"__#{module_attribute_name}s__"

    values_ast =
      for {value_name, values} <- module_attribute_values do
        quote do
          def unquote(singular)(unquote(to_string(value_name))), do: unquote(values)
          def unquote(singular)(unquote(value_name)), do: unquote(values)
        end
      end

    value_names = Enum.map(module_attribute_values, fn {name, _} -> name end)

    quote do
      unquote(values_ast)
      def unquote(singular)(_), do: nil
      def unquote(plural)(), do: unquote(value_names)
    end
  end

  defp expand_alias({:__aliases__, _, _} = ast, env), do: Macro.expand(ast, env)
  defp expand_alias(ast, _env), do: ast

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
end
