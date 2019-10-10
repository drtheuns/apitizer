defmodule Apitizer.Context do
  @moduledoc false

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
            assigns: %{}
end
