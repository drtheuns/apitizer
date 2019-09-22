defmodule Apitizer.RequestParserTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias Apitizer.RequestParser
  alias Apitizer.IncludeTree

  doctest IncludeTree, import: true

  describe "includes" do
    test "can be a comma-separated string" do
      tree = parse_includes("comments,author")

      assert map_size(tree.children) == 2
      assert IncludeTree.has_child?(tree, "comments")
      assert IncludeTree.has_child?(tree, "author")
    end

    test "can be a list" do
      tree = parse_includes(["comments", "author"])

      assert map_size(tree.children) == 2
      assert IncludeTree.has_child?(tree, "comments")
      assert IncludeTree.has_child?(tree, "author")
    end

    test "may be empty" do
      tree = parse_includes("")

      assert IncludeTree.is_empty?(tree)
    end

    test "may be missing" do
      conn = conn(:get, "/endpoint")
      tree = RequestParser.parse_includes(conn).assigns.includes

      assert IncludeTree.is_empty?(tree)
    end

    test "may contain nested includes" do
      tree = parse_includes("comments.author")

      assert IncludeTree.has_child?(tree, "comments")
      assert tree |> IncludeTree.get_child("comments") |> IncludeTree.has_child?("author")
    end

    test "may have multiple includes in the same tree" do
      tree = parse_includes("comments.author,comments.post,comments.author.profile")

      # Should look like %{comments => %{post => %{}, author => %{profile => %{}}}}

      assert IncludeTree.has_child?(tree, "comments")
      assert map_size(tree.children) == 1

      comments_tree = IncludeTree.get_child(tree, "comments")

      assert map_size(comments_tree.children) == 2

      assert comments_tree
             |> IncludeTree.get_child("author")
             |> IncludeTree.has_child?("profile")
    end
  end

  defp parse_includes(includes) do
    :get
    |> conn("/endpoints")
    |> Map.put(:query_string, get_include_query_string(includes))
    |> Plug.Conn.fetch_query_params()
    |> RequestParser.parse_includes()
    |> Map.get(:assigns)
    |> Map.get(:includes)
  end

  defp get_include_query_string(includes) when is_binary(includes) do
    "include=#{includes}"
  end

  defp get_include_query_string(includes) when is_list(includes) do
    includes
    |> Enum.map(fn include -> "include[]=#{include}" end)
    |> Enum.join("&")
  end
end
