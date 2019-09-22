defmodule Apitizer.RequestParser do
  @moduledoc """
  A plug that handles all the request parsing, such as the includes and filters.

  Each specific parser could also be used manually in case you don't need all
  of them.

  ## Options

      * `:include_key`: the key to the query parameter to use for includes.
        Defaults to `"include"`. Expects a string.
  """
  use Plug.Builder
  alias Apitizer.IncludeTree

  plug(:parse_includes, builder_opts())

  @doc """
  Parses the request's includes into a tree which will later be used by the
  ApiView to render (nested) includes.

  Supports includes as both a list, or a comma separated string:

      `GET /posts?include=author,comments.author`
      `GET /posts?include[]=author&include[]=comments.author`
  """
  def parse_includes(conn, opts \\ []) do
    include_key = Keyword.get(opts, :include_key, "include")

    includes =
      conn
      |> get_request_includes(include_key)
      |> IncludeTree.new_from_includes()

    # Must be set on the assigns, rather than the priv as we want to access them
    # in the views without the user having to manually specify them.
    assign(conn, :includes, includes)
  end

  defp get_request_includes(%Plug.Conn{} = conn, key) do
    case Map.get(conn.query_params, key) do
      includes when is_list(includes) -> includes
      includes when is_binary(includes) -> String.split(includes, ",", trim: true)
      _ -> []
    end
  end
end
