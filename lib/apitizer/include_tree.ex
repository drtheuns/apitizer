defmodule Apitizer.IncludeTree do
  @moduledoc false
  alias __MODULE__

  defstruct children: %{}, name: nil

  @type children :: %{(name :: String.t()) => t()}

  @type t :: %IncludeTree{
          name: String.t() | nil,
          children: children()
        }

  @doc """
  Construct a new include tree.
  """
  @spec new(String.t(), map()) :: t()
  def new(name \\ nil, children \\ %{}) do
    %IncludeTree{name: name, children: children}
  end

  @doc """
  Creates a new include tree from a list of includes as they were passed from
  the request.

  ## Example

      new_from_includes(["comments.author", "post"])
  """
  @spec new_from_includes([String.t()]) :: t()
  def new_from_includes(includes) when is_list(includes) do
    Enum.reduce(includes, new(), fn include, tree ->
      add_include(tree, include)
    end)
  end

  @doc """
  Add a child tree to an existing tree.

  ## Example

      iex> add_child(new(), new("comments"))
      %IncludeTree{name: nil, children: %{
        "comments" => %IncludeTree{name: "comments", children: %{}}
      }}
  """
  @spec add_child(t(), t()) :: t()
  def add_child(%IncludeTree{} = tree, %IncludeTree{} = child) do
    %{tree | children: Map.put(tree.children, child.name, child)}
  end

  @doc """
  Add an include to the given tree.

  The include can optionally contain nested includes.

  ## Example

      add_include(new(), "comments")
      add_include(new(), "comments.author.profile")
  """
  @spec add_include(t(), String.t()) :: t()
  def add_include(tree, include) when is_binary(include) do
    add_nested_include(tree, String.split(include, ".", trim: true))
  end

  defp add_nested_include(tree, []), do: tree

  defp add_nested_include(tree, [head | tail]) do
    case get_child(tree, head) do
      nil -> add_child(tree, add_nested_include(new(head), tail))
      node -> add_child(tree, add_nested_include(node, tail))
    end
  end

  @doc """
  Get a child tree based on the child's name.

  ## Example

      iex> get_child(new(), "comments")
      nil
      iex> get_child(add_include(new(), "comments"), "comments")
      %IncludeTree{name: "comments", children: %{}}
  """
  @spec get_child(t(), String.t()) :: t() | nil
  def get_child(tree, name) when is_binary(name) do
    tree.children[name]
  end

  @doc """
  Checks if the given child is a direct child of the given tree.

  ## Example

     iex> has_child?(new(), "comments")
     false
     iex> has_child?(add_include(new(), "comments"), "comments")
     true
  """
  @spec has_child?(t(), String.t()) :: boolean()
  def has_child?(tree, name) when is_binary(name) do
    get_child(tree, name) != nil
  end

  @doc """
  Checks if the the tree doesn't have any children.

  ## Example

      iex> is_empty?(new())
      true
      iex> is_empty?(add_include(new(), "comments"))
      false
  """
  @spec is_empty?(t()) :: boolean()
  def is_empty?(tree) do
    map_size(tree.children) == 0
  end
end
