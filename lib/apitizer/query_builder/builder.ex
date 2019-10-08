defmodule Apitizer.QueryBuilder.Builder do
  @moduledoc false
  # This module handles most of the metaprogramming needed to builder the query
  # builder modules.

  defmodule Attribute do
    defstruct [:name, :operators, :key, :alias, :apidoc, virtual: false, sortable: false]
  end

  defmodule Association do
    defstruct [:name, :builder, :key, :apidoc]
  end

  defmodule Filter do
    defstruct [:field, :operator, :apidoc]
  end

  defmodule Sort do
    defstruct [:field, :apidoc]
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

    quote do
      unquote(compile(:attribute, attributes))
      unquote(compile(:association, associations))
      unquote(compile(:filter, filters))
      unquote(compile(:sort, sorts))
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
    quote do
      def __sorts__(), do: unquote(Enum.map(sorts, fn {struct, _} -> struct end))
      unquote(Enum.map(sorts, fn {_, body} -> body end))
      def sort(_, _, _, _), do: nil
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
end
