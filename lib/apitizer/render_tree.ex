defmodule Apitizer.RenderTree do
  @moduledoc """
  This tree represents a graph to be rendered.

  ## Fields

    * `:name`: the name of the subtree as would be returned to the client.
    * `:key`: the key to the relation on the struct.
    * `:builder`: the builder module that will render this (sub)tree.
    * `:schema`: the ecto schema for this node.
    * `:fields`: the attribute fields to return in the response.
    * `:apidoc`: documentation for the node.
    * `:children`: the nested relationships to render.

  The `:key` and `:name` fields are `nil` for the root node.
  """

  defstruct [:name, :builder, :schema, :fields, :key, :apidoc, children: %{}]
end
