defmodule Apitizer.QueryBuilder do
  @moduledoc """
  Behaviour to implement a query builder.

  A query builder is responsible for generating a response based on an HTTP
  request. It supports complex expressions for selects, filters, and sorts.

  TODO: Example
  TODO: Selects
  TODO: Filters
  TODO: Sorting
  TODO: Extending
  TODO: APIDOC
  TODO: Callback cycle.
  """
  import Ecto.Query
  alias Apitizer.{Builder, Context, Interpreter}

  @doc """
  A query builder hook which is called before the filters are applied.

  At this point the query is essentially a newly created query.
  """
  @callback before_filters(Ecto.Queryable.t(), Context.t()) :: Ecto.Queryable.t()

  @doc """
  A query builder hook which is called after the selects are applied.
  """
  @callback after_filters(Ecto.Queryable.t(), Context.t()) :: Ecto.Queryable.t()

  @doc """
  A query builder hook which is called before the selects are applied.

  The selects are only applied to the current query. The before and after hooks
  are not called for the selects in the preloads.
  """
  @callback before_select(Ecto.Queryable.t(), Context.t()) :: Ecto.Queryable.t()

  @doc """
  A query builder hook which is called after the selects are applied.
  """
  @callback after_select(Ecto.Queryable.t(), Context.t()) :: Ecto.Queryable.t()

  @doc """
  A query builder hook which is called before the sorts are applied.
  """
  @callback before_sort(Ecto.Queryable.t(), Context.t()) :: Ecto.Queryable.t()

  @doc """
  A query builder hook which is called after the sorts are applied.
  """
  @callback after_sort(Ecto.Queryable.t(), Context.t()) :: Ecto.Queryable.t()

  @doc """
  A query builder hook which is called before the preloads are applied.
  """
  @callback before_preload(Ecto.Queryable.t(), Context.t()) :: Ecto.Queryable.t()

  @doc """
  A query builder hook which is called after the preloads are applied.
  """
  @callback after_preload(Ecto.Queryable.t(), Context.t()) :: Ecto.Queryable.t()

  @doc """
  Callback that is used to determine whether the caller may select an attribute
  or association.

  This is called while building the query. If these permissions aren't known for
  an attribute until the value is known, refer to `c:may_see?/3`.

  The atom of the first argument is the **name** of the attribute/assocation,
  not the key!

  Some fields are always fetched from the database: the primary key and the
  foreign keys needed to preload some related resource. For this reason, adding
  a `may_select?/2` callback for e.g. the primary key is not very useful.

  By default, this function will return `true`.
  """
  @callback may_select?(atom(), Context.t()) :: boolean

  @doc """
  Callback that is used to determine if the caller is allowed to see an
  attribute or association.

  This is called after the result of a query has been fetched, while building
  the final response map _before_ the transform function is called. Use this
  when the permissions of an attribute or association are only known once their
  values are known. If they're known earlier (e.g. based on the logged in user),
  prefer `c:may_select?/3`, as this might improve database performance.

  By default, this function will return `true`.
  """
  @callback may_see?(atom(), Ecto.Schema.t(), Context.t()) :: boolean

  @doc """
  Callback to determine is the caller is allowed to apply a sort to the query.

  In order to sort on attributes without a custom sort function this function
  must return true and the attribute must have `sortable: true`.

  This function is also called before custom sort functions defined using the
  `sort/5` macro. _Because_ custom sorts can be defined, this function is always
  called using a string field name, even for attributes.

  By default, this function will return `true`.
  """
  @callback may_sort?(String.t(), :asc | :desc, Context.t()) :: boolean

  @doc """
  Callback to determine if a user is allowed to apply a filter to the query.

  By default this function will return `true`.
  """
  @callback may_filter?(String.t() | :*, Apitizer.operator(), any, Context.t()) :: boolean

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

        got: #{inspect(schema)}
        """
    end

    quote do
      import Apitizer.QueryBuilder

      @before_compile Apitizer.Builder

      @behaviour Apitizer.QueryBuilder
      @operators [:eq, :neq, :gte, :gt, :lte, :lt, :in, :ilike, :like, :search]
      @default_operators [:eq, :neq]

      Module.register_attribute(__MODULE__, :apitizer_attributes, accumulate: true)
      Module.register_attribute(__MODULE__, :apitizer_associations, accumulate: true)
      Module.register_attribute(__MODULE__, :apitizer_filters, accumulate: true)
      Module.register_attribute(__MODULE__, :apitizer_sorts, accumulate: true)
      Module.register_attribute(__MODULE__, :apitizer_transforms, accumulate: true)
      Module.register_attribute(__MODULE__, :apidoc, accumulate: false)

      def __schema__, do: unquote(schema)
      def __repo__, do: unquote(repo)

      def query(conn, opts \\ []), do: Interpreter.query(__MODULE__, conn, opts)
      def one!(conn, id, opts \\ []), do: Interpreter.one!(__MODULE__, id, conn, opts)
      def paginate(conn, opts \\ []), do: Interpreter.paginate(__MODULE__, conn, opts)

      # Hooks
      def before_filters(query, _), do: query
      def after_filters(query, _), do: query
      def before_select(query, _), do: query
      def after_select(query, _), do: query
      def before_sort(query, _), do: query
      def after_sort(query, _), do: query
      def before_preload(query, _), do: query
      def after_preload(query, _), do: query

      # Permissions
      def may_select?(_field_or_assoc, _context), do: true
      def may_see?(_field_or_assoc, _resource, _context), do: true
      def may_sort?(_field_or_assoc, _sort_direction, _context), do: true
      def may_filter?(_field, _operator, _value, _context), do: true

      defoverridable before_filters: 2,
                     after_filters: 2,
                     before_select: 2,
                     after_select: 2,
                     before_sort: 2,
                     after_sort: 2,
                     before_preload: 2,
                     after_preload: 2,
                     query: 2,
                     one!: 2,
                     paginate: 2,
                     may_select?: 2,
                     may_see?: 3,
                     may_sort?: 3,
                     may_filter?: 4
    end
  end

  defp expand_alias({:__aliases__, _, _} = ast, env), do: Macro.expand(ast, env)
  defp expand_alias(ast, _env), do: ast

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
  defmacro attribute(name, opts \\ []) when is_atom(name) do
    quote do
      Builder.__attribute__(__MODULE__, unquote(name), unquote(opts))
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
      Builder.__association__(__MODULE__, unquote(name), unquote(builder), unquote(opts))
    end
  end

  @doc """
  Defines a filter.

  The filter must define an operator and a field that it filters.
  """
  defmacro filter(field, operator, value, query, dynamics, and_or, context, do: do_block)
           when (is_atom(field) or is_binary(field)) and is_atom(operator) do
    body =
      quote do
        def filter(unquote_splicing([field, operator, value, query, dynamics, and_or, context])),
          do: unquote(do_block)
      end

    quote do
      Builder.__filter__(__MODULE__, unquote(field), unquote(operator), unquote(body))
    end
  end

  @doc """
  Define a sort on a field.
  """
  defmacro sort(field, direction, query, context, do: do_block)
           when is_atom(field) or is_binary(field) do
    body =
      quote do
        def sort(unquote_splicing([field, direction, query, context])), do: unquote(do_block)
      end

    quote do
      Builder.__sort__(__MODULE__, unquote(field), unquote(body))
    end
  end

  @doc """
  Defines a transformation function on either an attribute or an association.
  """
  defmacro transform(field_or_assoc, value, resource, context, do: do_block)
           when is_atom(field_or_assoc) do
    body =
      quote do
        def transform(
              unquote(field_or_assoc),
              unquote(value),
              unquote(resource),
              unquote(context)
            ),
            do: unquote(do_block)
      end

    quote do
      Builder.__transform__(__MODULE__, unquote(field_or_assoc), unquote(body))
    end
  end

  @doc """
  Joins on the given `assoc` if the query doesn't yet have that named binding.

  This can be useful when you want to ensure a join exists, for example when it
  might or might not have already been created in an earlier filter.

  ## Example

  In the following code, only a one join will be performed on either query:

      from(post in Post) |> maybe_join(:comments)
      from(post in Post, join: c in assoc(post, :comments), as: :comments) |> maybe_join(:comments)
  """
  defmacro ensure_join(query, assoc, as \\ nil) when is_atom(assoc) and is_atom(as) do
    as = as || assoc

    quote do
      query = unquote(query)

      if has_named_binding?(query, unquote(as)) do
        query
      else
        from(q in query, join: assoc(q, unquote(assoc)), as: unquote(as))
      end
    end
  end

  @doc """
  Helper macro to extend a dynamic expression for both the "AND" and "OR" cases.

  This is particularly useful for custom filters where the and/or is not known up front.

  ## Example

  Assuming a database model in which a Task can be in a State (e.g. todo,
  completed, etc):

  ```elixir
  defmodule TaskBuilder do
    use Apitizer.QueryBuilder, schema: Task

    attribute :id
    attribute :time_estimate, operators: [:lte] # in seconds
    attribute :priority, operators: [:gte] # 1..5 (very low..very high)

    filter "states", :in, values, query, dynamics, and_or, _context do
      # Ensure the join exists.
      query = maybe_join(query, :state)

      # Add the WHERE clause.
      dynamics = extend_dynamics(dynamics, and_or, [state: state], state.name in ^values)

      {query, dynamics}
    end
  end
  ```

  The advantage of this, rather than placing it on the query directly, is that
  the caller is now free to place this "states" condition anywhere in their query:

      /tasks?filter=priority.gte.4,or(time_estimate.lte.60, states.in.(todo,waiting))

  Results in:

  ```sql
  select t0.id
    from tasks as t0
    join task_states as t1 on t0.state_id = t1.id
   where (t0.priority >= 4)
     and ((t0.time_estimate <= 60) or (t0.id = ANY(ARRAY['todo', 'waiting'])));
  ```
  """
  defmacro extend_dynamics(dynamics, and_or, bindings, expr) do
    quote do
      dynamics = unquote(dynamics)

      case unquote(and_or) do
        :and -> dynamic(unquote(bindings), unquote(expr) and ^dynamics)
        :or -> dynamic(unquote(bindings), unquote(expr) or ^dynamics)
      end
    end
  end
end
