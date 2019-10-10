defprotocol Apitizer.Pagination do
  @moduledoc """
  This protocol should be implemented if the `Apitizer.QueryBuilder.paginate/3`
  function is used.

  This protocol is responsible for turning a paginated result into a response.

  To turn a query into a paginated response, consult `Apitizer.QueryBuilder.paginate/3`.

  ## Example

  An example implementation for Scrivener:

  ```elixir
  defimpl Apitizer.Pagination, for: [Scrivener.Page] do
    def transform_entries(%Scrivener.Page{} = page, transform_func) do
        %{page | entries: Enum.map(page.entries, transform_func)}
    end

    def generate_response(%Scrivener.Page{} = page, _context) do
        Map.from_struct(page)
    end
  end
  ```
  """

  @doc """
  Transform the entries of the paginator.

  This applies the `select` expression from the request to the result that was
  fetched from the database.
  """
  @spec transform_entries(any, (Ecto.Schema.t() -> map())) :: any
  def transform_entries(resultset, transform_function)

  @doc """
  Renders the paginator to a response.

  This is similar to what a view function might do in Phoenix to generate a
  response from a paginator. This is called _after_ `transform_entries/2`.
  """
  @spec generate_response(any, Context.t()) :: any
  def generate_response(transformed_result, context)
end
