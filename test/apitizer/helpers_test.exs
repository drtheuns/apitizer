defmodule Apitizer.HelperTest do
  use ExUnit.Case, async: true
  import Apitizer.Helpers
  import Apitizer.IncludeTree, only: [new_from_includes: 1]

  defmodule Post do
    use Ecto.Schema
    @behaviour Apitizer.Includable

    schema "posts" do
      has_many(:comments, Apitizer.HelperTest.Comment)
      belongs_to(:author, Apitizer.HelperTest.User)
    end

    @impl Apitizer.Includable
    def include("comments"), do: :comments
    def include("author"), do: :author
    def include(_), do: nil
  end

  defmodule User do
    use Ecto.Schema
    @behaviour Apitizer.Includable

    schema "users" do
      has_many(:posts, Apitizer.HelperTest.Post)
    end

    @impl Apitizer.Includable
    def include("posts"), do: :posts
    def include(_), do: nil
  end

  defmodule Comment do
    use Ecto.Schema
    @behaviour Apitizer.Includable

    schema "comments" do
      belongs_to(:author, Apitizer.HelperTest.User)
      belongs_to(:post, Apitizer.HelperTest.Post)
    end

    @impl Apitizer.Includable
    def include("author"), do: :author
    def include("post"), do: :post
    def include(_), do: nil
  end

  describe "to_preload/2" do
    test "can generate simple preload expressions" do
      result = to_preload(new_from_includes(["comments", "author"]), Post)

      assert result == [:comments, :author]
    end

    test "can generate nested preload expressions" do
      result = to_preload(new_from_includes(["comments.author.posts"]), Post)

      assert result == [{:comments, [{:author, [:posts]}]}]
    end

    test "can generate nested preloads with the same parent" do
      result = to_preload(new_from_includes(["post.author", "post.comments"]), Comment)

      assert result == [{:post, [:comments, :author]}]
    end
  end
end
