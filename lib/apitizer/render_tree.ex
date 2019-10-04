defmodule Apitizer.RenderTree do
  @moduledoc """
  This tree represents a graph to be rendered.

  ## Fields

    * `:name`: the name of the subtree as would be returned to the client.
    * `:key`: the key to the relation on the struct.
    * `:builder`: the builder module that will render this (sub)tree.
    * `:fields`: the attribute fields to return in the response.
    * `:children`: the nested relationships to render.

  The `:key` and `:name` fields are `nil` for the root node.
  """
  alias __MODULE__

  defstruct [:name, :builder, :fields, :key, children: %{}]

  def new(name, key, builder, fields, children \\ %{}) do
    %RenderTree{name: name, key: key, builder: builder, fields: fields, children: children}
  end
end
