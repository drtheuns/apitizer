defmodule Apitizer.QueryBuilderTest do
  use ExUnit.Case, async: true

  defmodule UserQueryBuilder do
    use Apitizer.QueryBuilder
    import Ecto.Query

    def filter("user", query, value) do
      from(u in query, where: u.id == ^value)
    end

    def filter("stop", _, :now), do: cancel()
    def filter("stop", _, :boom), do: cancel(:stop_with_return_value)
  end

  defmodule User do
    use Ecto.Schema

    schema "users" do
      field(:email, :string)
      field(:password_hash, :string)
    end
  end

  defp filter(params) do
    UserQueryBuilder.build(User, params)
  end

  describe "basic filtering" do
    test "it should apply query filters if they exist" do
      query = filter([{"user", 1}])
      assert length(query.wheres) == 1
    end

    test "it should skip unknown filters" do
      query = filter([{"unknown", "hello"}])
      # It didn't build any filters, so the query is still the same as the one
      # passed in.
      assert query == User
    end
  end

  describe "cancelling queries" do
    test "we can cancel further filters and return the current query" do
      query = filter([{"user", 1}, {"stop", :now}])
      assert length(query.wheres) == 1

      query = filter([{"user", 1}, {"stop", :boom}])
      assert query == :stop_with_return_value
    end
  end
end
