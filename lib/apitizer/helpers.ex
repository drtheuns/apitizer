defmodule Apitizer.Helpers do
  @moduledoc """
  Helper functions to simplify working Apitizer specific functionality.
  """

  alias Apitizer.IncludeTree

  @doc """
  Turn the parsed includes into a preload keyword list that Ecto can understand.

  As of right now, there is no support for custom preload functions.
  """
  @spec to_preload(Plug.Conn.t() | IncludeTree.t(), Apitizer.Includeable) :: list()
  def to_preload(%Plug.Conn{assigns: %{includes: includes}}, schema),
    do: to_preload(includes, schema)

  def to_preload(%IncludeTree{} = tree, schema) do
    Enum.reduce(tree.children, [], fn {include, child_tree}, acc ->
      case get_include_key(schema, include) do
        nil ->
          acc

        key ->
          if IncludeTree.is_empty?(child_tree) do
            [key | acc]
          else
            case get_related_model(schema, key) do
              nil -> [key | acc]
              related_schema -> [{key, to_preload(child_tree, related_schema)} | acc]
            end
          end
      end
    end)
  end

  def to_preload(_, _), do: []

  defp get_include_key(schema, include) do
    if function_exported?(schema, :include, 1) do
      schema.include(include)
    else
      nil
    end
  end

  defp get_related_model(schema, relation) do
    if function_exported?(schema, :__schema__, 2) do
      schema.__schema__(:association, relation).related
    else
      nil
    end
  end
end
