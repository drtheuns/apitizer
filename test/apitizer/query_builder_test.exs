defmodule Apitizer.QueryBuilderTest do
  use ExUnit.Case, async: true

  defmodule User do
    use Ecto.Schema

    schema "users" do
      field(:name, :string)
      has_many(:posts, Apitizer.QueryBuilderTest.Post)
    end
  end

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field(:title, :string)
      belongs_to(:user, Apitizer.QueryBuilderTest.User)
    end
  end

  defmodule UserBuilder do
    use Apitizer.QueryBuilder, schema: Apitizer.QueryBuilderTest.User

    attribute(:id, operators: [:eq, :neq])
    attribute(:name)

    association(:posts, Apitizer.QueryBuilderTest.PostBuilder)
  end

  defmodule PostBuilder do
    use Apitizer.QueryBuilder, schema: Apitizer.QueryBuilderTest.Post

    attribute(:id)
  end

  describe "reflection" do
    test "exposes the declared attributes" do
      assert UserBuilder.__attributes__() == [:id, :name]

      assert UserBuilder.__attribute__(:id) == %Apitizer.QueryBuilder.Attribute{
               sortable: false,
               operators: [:eq, :neq],
               name: :id,
               key: :id,
               alias: :id
             }
    end

    test "exposes the schema" do
      assert UserBuilder.__schema__() == User
    end

    test "exposes the declared associations" do
      assert UserBuilder.__associations__() == [:posts]

      assert UserBuilder.__association__(:posts) == %Apitizer.QueryBuilder.Association{
               name: :posts,
               builder: Apitizer.QueryBuilderTest.PostBuilder,
               key: :posts
             }
    end
  end

  test "it should raise when missing a schema" do
    assert_raise ArgumentError, fn ->
      defmodule FailBuilder do
        use Apitizer.QueryBuilder
      end
    end
  end
end
