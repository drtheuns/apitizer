defmodule Apitizer.Utils do
  @moduledoc false

  @doc """
  Get an option from a keyword list if it exists, otherwise, attempt to fetch it
  from the config, fallback to default key.
  """
  def option_or_config(opts, key, default) do
    Keyword.get_lazy(opts, key, fn ->
      Application.get_env(:apitizer, key, default)
    end)
  end
end
