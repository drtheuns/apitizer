defmodule Apitizer do
  @typedoc """
  The allowed operators in filter expressions.
  """
  @type operator ::
          :eq | :neq | :gte | :gt | :lte | :lt | :search | :ilike | :like | :contains | :in

  @typedoc """
  The directions that are allowed in sort expressions.
  """
  @type sort_direction :: :asc | :desc
end
