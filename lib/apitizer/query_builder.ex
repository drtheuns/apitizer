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
  alias Apitizer.QueryBuilder.{Builder, Context, Interpreter}

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

      @before_compile Apitizer.QueryBuilder.Builder

      @behaviour Apitizer.QueryBuilder
      @operators [:eq, :neq, :gte, :gt, :lte, :lt, :in, :ilike, :like, :search]
      @default_operators [:eq, :neq]

      Module.register_attribute(__MODULE__, :apitizer_attributes, accumulate: true)
      Module.register_attribute(__MODULE__, :apitizer_associations, accumulate: true)
      Module.register_attribute(__MODULE__, :apitizer_filters, accumulate: true)
      Module.register_attribute(__MODULE__, :apitizer_sorts, accumulate: true)
      Module.register_attribute(__MODULE__, :apidoc, accumulate: false)

      def __schema__, do: unquote(schema)
      def __repo__, do: unquote(repo)

      def query(conn, opts \\ []), do: Interpreter.query(__MODULE__, conn, opts)
      def one!(conn, opts \\ []), do: Interpreter.one!(__MODULE__, conn, opts)
      def all(conn, opts \\ []), do: Interpreter.all(__MODULE__, conn, opts)
      def paginate(conn, opts \\ []), do: Interpreter.paginate(__MODULE__, conn, opts)

      def before_filters(query, _), do: query
      def after_filters(query, _), do: query
      def before_select(query, _), do: query
      def after_select(query, _), do: query
      def before_sort(query, _), do: query
      def after_sort(query, _), do: query
      def before_preload(query, _), do: query
      def after_preload(query, _), do: query

      defoverridable before_filters: 2,
                     after_filters: 2,
                     before_select: 2,
                     after_select: 2,
                     before_sort: 2,
                     after_sort: 2,
                     before_preload: 2,
                     after_preload: 2
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
end
