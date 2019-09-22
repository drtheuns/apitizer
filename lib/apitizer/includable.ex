defmodule Apitizer.Includable do
  @moduledoc """
  This behaviour allows models to specify how includes should be mapped to the
  keys on a struct. It was primarily created with Ecto schemas in mind.
  """

  @doc """
  Get the name of the relation on the model that can be used to render the
  include. Returning `nil` will ignore this include.
  """
  @callback include(String.t()) :: String.t() | atom() | nil
end
