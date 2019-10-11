defmodule Apitizer.Context do
  @moduledoc """
  The context struct is used to hold information about the current request.

  It is very similar to a Plug.Conn object.
  """

  @type t :: %__MODULE__{
          filter_key: String.t(),
          sort_key: String.t(),
          select_key: String.t(),
          repo: module,
          repo_function: (Ecto.Queryable.t(), t -> any),
          raw_filters: nil | String.t(),
          raw_sort: nil | String.t(),
          raw_select: nil | String.t(),
          parsed_filters: Apitizer.Parser.filter_and_or(),
          parsed_sort: [Apitizer.Parser.sort()],
          parsed_select: [Apitizer.Parser.select_field()],
          assigns: map(),
          max_depth: pos_integer | :infinite
        }

  defstruct filter_key: nil,
            sort_key: nil,
            select_key: nil,
            repo: nil,
            repo_function: nil,
            raw_filters: nil,
            raw_sort: nil,
            raw_select: nil,
            parsed_filters: nil,
            parsed_sort: nil,
            parsed_select: nil,
            render_tree: nil,
            max_depth: 4,
            assigns: %{}
end
