defmodule Apitizer.Builder do
  @moduledoc false
  # This module handles most of the metaprogramming needed to builder the query
  # builder modules.

  defmodule Attribute do
    @moduledoc false
    defstruct [
      :name,
      :operators,
      :key,
      :alias,
      :apidoc,
      virtual: false,
      sortable: false
    ]
  end

  defmodule Association do
    @moduledoc false
    defstruct [:name, :builder, :key, :apidoc]
  end

  defmodule Filter do
    @moduledoc false
    defstruct [:field, :operator, :apidoc]
  end

  defmodule Sort do
    @moduledoc false
    defstruct [:field, :apidoc]
  end

  defmodule Transform do
    @moduledoc false
    # type: :assocation | :attribute
    defstruct [:field, :type]
  end

  def __attribute__(module, name, opts) do
    opts =
      opts
      |> Keyword.put_new(:operators, Module.get_attribute(module, :default_operators))
      |> Keyword.put_new(:key, name)
      |> Keyword.put(:name, name)
      |> Keyword.put(:alias, name)
      |> Keyword.put(:apidoc, apidoc(module))

    struct = struct(Attribute, opts) |> Macro.escape()

    Module.put_attribute(module, :apitizer_attributes, {name, struct})
  end

  def __association__(module, name, builder, opts) do
    opts =
      opts
      |> Keyword.put(:name, name)
      |> Keyword.put(:builder, builder)
      |> Keyword.put_new(:key, name)
      |> Keyword.put(:apidoc, apidoc(module))

    struct = struct(Association, opts) |> Macro.escape()

    Module.put_attribute(module, :apitizer_associations, {name, struct})
  end

  def __filter__(module, field, operator, body) do
    struct = %Filter{field: field, operator: operator, apidoc: apidoc(module)} |> Macro.escape()

    Module.put_attribute(module, :apitizer_filters, {struct, body})
  end

  def __sort__(module, field, body) do
    struct = %Sort{field: field, apidoc: apidoc(module)} |> Macro.escape()

    Module.put_attribute(module, :apitizer_sorts, {struct, body})
  end

  def __transform__(module, field_or_assoc, body) do
    Module.put_attribute(module, :apitizer_transforms, {field_or_assoc, body})
  end

  defp apidoc(module) do
    result = Module.get_attribute(module, :apidoc)
    Module.delete_attribute(module, :apidoc)
    result
  end

  defmacro __before_compile__(env) do
    attributes = Module.get_attribute(env.module, :apitizer_attributes)
    associations = Module.get_attribute(env.module, :apitizer_associations)
    filters = Module.get_attribute(env.module, :apitizer_filters)
    sorts = Module.get_attribute(env.module, :apitizer_sorts)

    # We can only build this now, once all the other attributes are known.
    transforms =
      env.module
      |> Module.get_attribute(:apitizer_transforms)
      |> Enum.reduce([], fn {field, body}, acc ->
        cond do
          transform_type?(field, attributes) ->
            [{%Transform{field: field, type: :attribute} |> Macro.escape(), body} | acc]

          transform_type?(field, associations) ->
            [{%Transform{field: field, type: :association} |> Macro.escape(), body} | acc]

          true ->
            acc
        end
      end)

    quote do
      unquote(compile(:attribute, attributes))
      unquote(compile(:association, associations))
      unquote(compile(:filter, filters))
      unquote(compile(:sort, sorts))
      unquote(compile(:transform, transforms))
    end
  end

  defp compile(:filter, filters) do
    quote do
      def __filters__(), do: unquote(Enum.map(filters, fn {struct, _} -> struct end))
      unquote(Enum.map(filters, fn {_, body} -> body end))
      def filter(_, _, _, _, _, _, _), do: nil
    end
  end

  defp compile(:sort, sorts) do
    singular =
      for %{field: field} = sort <- sorts do
        quote do
          def __sort__(unquote(field)), do: unquote(sort)
          def __sort__(unquote(to_string(field))), do: unquote(sort)
        end
      end

    quote do
      def __sorts__(), do: unquote(Enum.map(sorts, fn {struct, _} -> struct end))
      unquote(singular)
      unquote(Enum.map(sorts, fn {_, body} -> body end))
      def sort(_, _, _, _), do: nil
    end
  end

  defp compile(:transform, transforms) do
    singular =
      for %{field: field} = transform <- transforms do
        quote do
          def __transform__(unquote(field)), do: unquote(transform)
          def __transform__(unquote(to_string(field))), do: unquote(transform)
        end
      end

    quote do
      def __transforms__(), do: unquote(Enum.map(transforms, fn {struct, _} -> struct end))
      unquote(singular)
      unquote(Enum.map(transforms, fn {_, body} -> body end))
      def transform(_field, value, _resource, _context), do: value
    end
  end

  # Compiles all the different attributes and associations to introspectable
  # functions. Everything should be "queryable" by name as either a string or an
  # atom (e.g. __attribute__(:name) & __attribute__("name")) and the full list
  # of keys can be fetched using the plural, e.g.: __attributes__, __filters__,
  # etc
  defp compile(module_attribute_name, module_attribute_values) do
    singular = :"__#{module_attribute_name}__"
    plural = :"__#{module_attribute_name}s__"

    values_ast =
      for {value_name, values} <- module_attribute_values do
        quote do
          def unquote(singular)(unquote(to_string(value_name))), do: unquote(values)
          def unquote(singular)(unquote(value_name)), do: unquote(values)
        end
      end

    value_names = Enum.map(module_attribute_values, fn {name, _} -> name end)

    quote do
      unquote(values_ast)
      def unquote(singular)(_), do: nil
      def unquote(plural)(), do: unquote(value_names)
    end
  end

  defp transform_type?(_transform, []), do: false

  defp transform_type?(transform, [{_, struct} | tail]) do
    if kv_in_ast_struct?({:key, transform}, struct) do
      true
    else
      transform_type?(transform, tail)
    end
  end

  defp kv_in_ast_struct?(kv, {:%{}, [], keywords}) do
    keyword_has_kv?(kv, keywords)
  end

  defp keyword_has_kv?(_, []), do: false
  defp keyword_has_kv?({key, value}, [{key, value} | _]), do: true
  defp keyword_has_kv?(kv, [_ | tail]), do: keyword_has_kv?(kv, tail)
end
