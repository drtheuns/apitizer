defmodule Apitizer.QueryBuilder do
  @moduledoc """
  A generalized filter class to build filtering of a request to a query.

  ## Example

  The following module support one filter, user, which will filter the query
  down to a specific user id. In a JSON-API implementation, the filter might
  be passed in the request as `/users?filter[user]=5`

      defmodule UserFilter do
        use Apitizer.Filter
        import Ecto.Query

        def filter("user", query, value) do
          from u in query, where: u.user_id == ^value
        end
      end

      defmodule UserController do
        def index(conn, params) do
          users = UserFilter.build(User, params) |> Repo.all()
          render(conn, "index.json", users: users)
        end
      end
  """

  # TODO: Add some kind of context object, like the conn.assigns, that is passed
  # to each filter. This allows users of the filter to add, for example, the
  # conn or current_user to the filters.

  defmacro __using__(_opts) do
    quote do
      import Apitizer.QueryBuilder
      @before_compile Apitizer.QueryBuilder

      def build(queryable, params), do: build(__MODULE__, queryable, params)
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def filter(_, query, _), do: query
    end
  end

  @spec build(module, Ecto.Queryable.t(), map | keyword) :: Ecto.Queryable.t()
  def build(_module, queryable, nil), do: queryable
  def build(_module, queryable, []), do: queryable
  def build(module, queryable, %{"filter" => filters}), do: build(module, queryable, filters)

  def build(module, queryable, params) do
    Enum.reduce_while(params, queryable, fn {k, v}, query ->
      case module.filter(k, queryable, v) do
        :stop -> {:halt, query}
        {:stop, return} -> {:halt, return}
        query -> {:cont, query}
      end
    end)
  end

  def cancel do
    :stop
  end

  def cancel(return) do
    {:stop, return}
  end
end
